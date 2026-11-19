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
      -m, --minsup <threshold>  Minimum support: float in (0, 1] for relative or int >= 1 for absolute [Required]
      -o, --output <path>       Path to output file (default: "output.txt")
      -a, --algo <name>         Solver implementation: "baseline" or "optimized" (default: "baseline")
      -w, --warmup <0|1>        1 = chạy thử trên vài giao dịch trước khi bấm giờ để loại thời gian JIT (default: 0)
      -h, --help                Show this help message and exit
    """)
end

function parse_cli_args(args::Vector{String})::Dict{String, String}
    opts = Dict{String, String}()
    alias_map = Dict(
        "-i" => "input",  "--input"  => "input",
        "-m" => "minsup", "--minsup" => "minsup",
        "-o" => "output", "--output" => "output",
        "-a" => "algo",   "--algo"   => "algo",
        "-w" => "warmup", "--warmup" => "warmup"
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
    if occursin('.', raw) || occursin('e', lowercase(raw))
        val = tryparse(Float64, raw)
        (val === nothing || val <= 0.0 || val > 1.0) &&
            error("ArgumentError: Relative --minsup must be a float in (0.0, 1.0], got '$raw'.")
        return val
    else
        val = tryparse(Int, raw)
        (val === nothing || val < 1) &&
            error("ArgumentError: Absolute --minsup must be an integer >= 1, got '$raw'.")
        return val
    end
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

    opts = parse_cli_args(ARGS)
    input_path = get(opts, "input") do
        error("ArgumentError: Missing required argument --input <path>.")
    end
    minsup_raw = get(opts, "minsup") do
        error("ArgumentError: Missing required argument --minsup <threshold>.")
    end
    output_path = get(opts, "output", "output.txt")
    algo_name   = get(opts, "algo", "baseline")

    minsup = parse_minsup(minsup_raw)
    solver = build_solver(algo_name)

    if get(opts, "warmup", "0") == "1" # biên dịch trước (đọc, fit!, ghi) để thời gian đo không chứa JIT
        warm_tx = read_spmf_transactions(input_path)
        warm = build_solver(algo_name)
        fit!(warm, warm_tx[1:min(200, length(warm_tx))], 0.5)
        warm_out = tempname()
        save_spmf(warm, warm_out)
        rm(warm_out, force=true)
    end
    read_stats = @timed read_spmf_transactions(input_path)
    transactions = read_stats.value
    stats = @timed fit!(solver, transactions, minsup)
    write_stats = @timed save_spmf(solver, output_path)

    elapsed_ms = round(stats.time * 1000, digits=2)
    total_ms = round((read_stats.time + stats.time + write_stats.time) * 1000, digits=2)
    println("[$(typeof(solver))] Transactions: $(solver.num_transactions) | MinSup Count: $(solver.minsup_count) | Closed Itemsets: $(length(solver.closed_itemsets)) | Read: $(round(read_stats.time * 1000, digits=2)) ms | Time: $(elapsed_ms) ms | Write: $(round(write_stats.time * 1000, digits=2)) ms | Total: $(total_ms) ms | PeakRSS: $(round(Sys.maxrss() / 2^20, digits=1)) MB")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end