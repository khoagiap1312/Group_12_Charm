include(joinpath(@__DIR__, "interfaces.jl"))
include(joinpath(@__DIR__, "io_utils.jl"))
include(joinpath(@__DIR__, "algorithm", "baseline_solver.jl"))
include(joinpath(@__DIR__, "algorithm", "charm_core.jl"))
include(joinpath(@__DIR__, "algorithm", "optimized_solver.jl"))

function print_usage()
    println("""
    CHARM Frequent Closed Itemset Mining - CLI

    Usage:
      julia src/main.jl --input <path> --minsup <threshold> [--output <path>] [--algo <name>]

    Options:
      -i, --input <path>        Path to input transaction file (SPMF .txt format) [Required]
      -m, --minsup <threshold>  Minimum support [Required]. Supports 3 formats:
                                  • Percentage (SPMF-style): e.g. "40%", "33.3%" (0% < m <= 100%)
                                  • Relative fraction:       e.g. 0.4, 0.33 (0.0 < m <= 1.0)
                                  • Absolute count:          e.g. 3, 10 (integer >= 1)
      -o, --output <path>       Path to output file (default: "output.txt")
      -a, --algo <name>         Solver implementation: "baseline" or "optimized" (default: "baseline")
      -w, --warmup <0|1>        1 = compile first on a few transactions so the timing excludes JIT (default: 0)
      -r, --order <name>        Item processing order: none | support_asc | support_desc (default: none).
                                Only affects speed, the mined itemsets are identical.
      -h, --help                Show this help message and exit

    Examples:
      julia src/main.jl -i data/toy/sample.txt -m 40% -a optimized
      julia src/main.jl -i data/toy/sample.txt -m 0.4 -o result.txt
      julia src/main.jl -i data/toy/sample.txt -m 3 -a baseline
    """)
end

function parse_cli_args(args::Vector{String})::Dict{String, String}
    opts = Dict{String, String}()
    alias_map = Dict(
        "-i" => "input",  "--input"  => "input",
        "-m" => "minsup", "--minsup" => "minsup",
        "-o" => "output", "--output" => "output",
        "-a" => "algo",   "--algo"   => "algo",
        "-w" => "warmup", "--warmup" => "warmup",
        "-r" => "order",  "--order"  => "order"
    )

    i = 1
    while i <= length(args)
        flag = args[i]
        if haskey(alias_map, flag)
            i == length(args) && error("ArgumentError: Missing value after flag '$flag'.")
            opts[alias_map[flag]] = args[i + 1]
            i += 2
        else
            error("ArgumentError: Unknown or malformed CLI argument '$flag'. Run with --help for usage.")
        end
    end
    return opts
end

function parse_minsup(raw::AbstractString)::Real
    s = strip(raw)
    if endswith(s, "%")
        val = tryparse(Float64, s[1:end-1])
        (val === nothing || val <= 0.0 || val > 100.0) &&
            error("ArgumentError: Percentage minsup must be in (0%, 100%], got '$raw'.")
        return val / 100.0
    end
    if occursin('.', s) || occursin('e', lowercase(s))
        val = tryparse(Float64, s)
        (val === nothing || val <= 0.0 || val > 1.0) &&
            error("ArgumentError: Relative minsup must be a float in (0.0, 1.0], got '$raw'.")
        return val
    end
    val = tryparse(Int, s)
    (val === nothing || val < 1) &&
        error("ArgumentError: Absolute minsup must be an integer >= 1, got '$raw'.")
    return val
end

function build_solver(algo_name::AbstractString)::AbstractCharmSolver
    name = lowercase(strip(algo_name))
    if name == "baseline"
        return BaselineCharmSolver()
    elseif name == "optimized"
        if @isdefined(OptimizedCharmSolver)
            return OptimizedCharmSolver()
        else
            error("NotImplementedError: OptimizedCharmSolver is not loaded yet (check src/algorithm/optimized_solver.jl).")
        end
    else
        error("ArgumentError: Unsupported --algo '$algo_name'. Choose 'baseline' or 'optimized'.")
    end
end

function main()
    if isempty(ARGS) || "--help" in ARGS || "-h" in ARGS
        print_usage()
        return
    end
    try
        opts = parse_cli_args(ARGS)
        input_path = get(opts, "input") do
            error("ArgumentError: Missing required parameter --input <path>.")
        end
        minsup_raw = get(opts, "minsup") do
            error("ArgumentError: Missing required parameter --minsup <threshold>.")
        end
        output_path = get(opts, "output", "output.txt")
        algo_name   = get(opts, "algo", "baseline")
        minsup = parse_minsup(minsup_raw)
        solver = build_solver(algo_name)
        order = Symbol(lowercase(strip(get(opts, "order", "none"))))

        if get(opts, "warmup", "0") == "1" # compile first (read, fit!, write) so the timing excludes JIT
            warm_tx = read_spmf_transactions(input_path)
            warm = build_solver(algo_name)
            fit!(warm, warm_tx[1:min(200, length(warm_tx))], 0.5; order)
            warm_out = tempname()
            save_spmf(warm, warm_out)
            rm(warm_out, force=true)
        end
        read_stats = @timed read_spmf_transactions(input_path)
        transactions = read_stats.value
        stats = @timed fit!(solver, transactions, minsup; order)
        write_stats = @timed save_spmf(solver, output_path)

        elapsed_ms = round(stats.time * 1000, digits=2)
        total_ms = round((read_stats.time + stats.time + write_stats.time) * 1000, digits=2)
        println("[$(typeof(solver))] Transactions: $(solver.num_transactions) | MinSup Count: $(solver.minsup_count) | Closed Itemsets: $(length(solver.closed_itemsets)) | Read: $(round(read_stats.time * 1000, digits=2)) ms | Time: $(elapsed_ms) ms | Write: $(round(write_stats.time * 1000, digits=2)) ms | Total: $(total_ms) ms | PeakRSS: $(round(Sys.maxrss() / 2^20, digits=1)) MB")
    catch e
        println(stderr, "Error: ", e isa ErrorException ? e.msg : sprint(showerror, e))
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
