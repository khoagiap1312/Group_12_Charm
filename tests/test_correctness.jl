using Test
using Printf

include(joinpath(@__DIR__, "..", "src", "structures.jl"))
include(joinpath(@__DIR__, "..", "src", "interfaces.jl"))
include(joinpath(@__DIR__, "..", "src", "io_utils.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "baseline_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "optimized_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "charm_core.jl"))

# ── Helper: Đọc file output SPMF thành Dict{Set{Int} => Support} ──
function parse_spmf_file(filepath::AbstractString)::Dict{Set{Int}, Int}
    result = Dict{Set{Int}, Int}()
    !isfile(filepath) && return result
    for line in eachline(filepath)
        s = strip(line)
        (isempty(s) || startswith(s, "@") || startswith(s, "#") || !occursin("#SUP:", s)) && continue
        parts = split(s, "#SUP:")
        items = Set(parse(Int, tok) for tok in split(strip(parts[1])))
        sup = parse(Int, strip(parts[2]))
        result[items] = sup
    end
    return result
end

function to_dict(solver::AbstractCharmSolver)::Dict{Set{Int}, Int}
    return Dict(Set(items) => sup for (items, sup) in solver.closed_itemsets)
end

struct EvalSummary
    dataset::String
    minsup::String
    solver::String
    spmf_cnt::Int
    ours_cnt::Int
    matched::Int
    rate::Float64
end

@testset verbose=true "Group 12 CHARM - Automated Correctness Verification" begin

    datasets = [
        ("sample",             joinpath(@__DIR__, "..", "data", "toy", "sample.txt"),             2, "33.3%"),
        ("contextPasquier99",  joinpath(@__DIR__, "..", "data", "toy", "contextPasquier99.txt"),  2, "40%"),
        ("contextZart",        joinpath(@__DIR__, "..", "data", "toy", "contextZart.txt"),        2, "40%"),
        ("contextItemsetTree", joinpath(@__DIR__, "..", "data", "toy", "contextItemsetTree.txt"), 2, "25%"),
        ("contextRelim",       joinpath(@__DIR__, "..", "data", "toy", "contextRelim.txt"),       2, "20%"),
    ]

    spmf_jar = joinpath(@__DIR__, "spmf.jar")
    has_java = Sys.which("java") !== nothing && isfile(spmf_jar)
    summary_table = EvalSummary[]

    println(" Automated test on 5 datasets and compare with spmf")

    for (name, path, minsup_abs, minsup_pct) in datasets
        @testset "Dataset: $name (minsup=$minsup_abs)" begin
            @test isfile(path)
            transactions = read_spmf_transactions(path)
            @test !isempty(transactions)

            #lấy kết quả tham chiếu từ SPMF
            spmf_dict = Dict{Set{Int}, Int}()
            tmp_spmf_out = tempname() * ".txt"

            if has_java
                #tự động chạy SPMF sinh kết quả chuẩn
                run(pipeline(`java -jar $spmf_jar run Charm_bitset $path $tmp_spmf_out $minsup_pct`, devnull))
                spmf_dict = parse_spmf_file(tmp_spmf_out)
                rm(tmp_spmf_out, force=true)
            else
                # Đọc file SPMF reference đã sinh sẵn trong tests/expected/
                ref_file = joinpath(@__DIR__, "expected", "spmf_output_$name.txt")
                spmf_dict = parse_spmf_file(ref_file)
            end

            @test !isempty(spmf_dict)
            num_spmf = length(spmf_dict)

            #Test BaselineCharmSolver
            base_solver = BaselineCharmSolver()
            fit!(base_solver, transactions, minsup_abs)
            base_dict = to_dict(base_solver)

            @test length(base_dict) == num_spmf
            @test base_dict == spmf_dict  # Kiểm tra khớp 100% cả itemset và support

            matched_base = count(k -> get(spmf_dict, k, -1) == get(base_dict, k, -2), keys(base_dict))
            rate_base = (matched_base / num_spmf) * 100.0
            push!(summary_table, EvalSummary(name, "$minsup_abs", "Baseline", num_spmf, length(base_dict), matched_base, rate_base))

            #Test OptimizedCharmSolver
            opt_solver = OptimizedCharmSolver()
            fit!(opt_solver, transactions, minsup_abs)
            opt_dict = to_dict(opt_solver)

            @test length(opt_dict) == num_spmf
            @test opt_dict == spmf_dict
            @test opt_dict == base_dict   # Cross-check với baseline

            matched_opt = count(k -> get(spmf_dict, k, -1) == get(opt_dict, k, -2), keys(opt_dict))
            rate_opt = (matched_opt / num_spmf) * 100.0
            push!(summary_table, EvalSummary(name, "$minsup_abs", "Optimized", num_spmf, length(opt_dict), matched_opt, rate_opt))
        end
    end

    println("\n" * "="^96)
    @printf("%-20s | %-6s | %-10s | %-9s | %-9s | %-9s | %-10s\n",
            "Dataset", "MinSup", "Solver", "SPMF Cnt", "Ours Cnt", "Matched", "Match Rate")
    println("-"^96)
    for r in summary_table
        @printf("%-20s | %-6s | %-10s | %-9d | %-9d | %-9d | %9.2f%%\n",
                r.dataset, r.minsup, r.solver, r.spmf_cnt, r.ours_cnt, r.matched, r.rate)
    end
    println("="^96 * "\n")
end