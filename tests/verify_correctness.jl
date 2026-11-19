using Printf

include(joinpath(@__DIR__, "..", "src", "interfaces.jl"))
include(joinpath(@__DIR__, "..", "src", "io_utils.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "baseline_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "optimized_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "charm_core.jl"))

struct VerificationResult
    dataset::String
    minsup::String
    solver::String
    spmf_count::Int
    ours_count::Int
    exact_matches::Int
    missing_count::Int
    extra_count::Int
    wrong_sup_count::Int
    duplicate_count::Int
    match_rate::Float64
end

# Đọc file kết quả chuẩn SPMF
# Trả về Dict(Set{Int} => Int) và số dòng bị trùng lặp (nếu có).
function parse_spmf_file(filepath::String)
    if !isfile(filepath)
        error("Không tìm thấy file: $filepath")
    end

    itemsets = Dict{Set{Int}, Int}()
    duplicates = 0

    for line in eachline(filepath)
        s = strip(line)
        (isempty(s) || startswith(s, "@") || startswith(s, "#")) && continue

        parts = split(s, "#SUP:")
        length(parts) != 2 && error("Malformed line format in $filepath: $s")

        items_str, sup_str = strip(parts[1]), strip(parts[2])
        items = isempty(items_str) ? Set{Int}() : Set(parse.(Int, split(items_str)))
        sup = parse(Int, sup_str)

        if haskey(itemsets, items)
            duplicates += 1
        else
            itemsets[items] = sup
        end
    end

    return itemsets, duplicates
end

# Đối chiếu kết quả của nhóm với file chuẩn SPMF.
function verify_pair(dataset::String, minsup::String, solver::String, spmf_path::String, ours_path::String)
    spmf_map, _ = parse_spmf_file(spmf_path)
    ours_map, ours_dups = parse_spmf_file(ours_path)

    spmf_keys = keys(spmf_map)
    ours_keys = keys(ours_map)

    common_keys = intersect(spmf_keys, ours_keys)
    missing_keys = setdiff(spmf_keys, ours_keys)
    extra_keys = setdiff(ours_keys, spmf_keys)

    exact_matches = 0
    wrong_sup_keys = Set{Int}[]

    for k in common_keys
        if spmf_map[k] == ours_map[k]
            exact_matches += 1
        else
            push!(wrong_sup_keys, k)
        end
    end

    total_union = length(union(spmf_keys, ours_keys))
    match_rate = total_union == 0 ? 100.0 : (exact_matches / total_union) * 100.0

    if match_rate < 100.0 || ours_dups > 0
        println("\n[DISCREPANCY WARNING] $dataset ($minsup) - $solver:")
        ours_dups > 0 && println("  - Output duplicates: $ours_dups")
        if !isempty(missing_keys)
            sample = sort(collect(first(missing_keys)))
            println("  - Missing $(length(missing_keys)) itemset(s) (e.g., $sample, #SUP SPMF = $(spmf_map[first(missing_keys)]))")
        end
        if !isempty(extra_keys)
            sample = sort(collect(first(extra_keys)))
            println("  - Extra $(length(extra_keys)) itemset(s) (e.g., $sample, #SUP Ours = $(ours_map[first(extra_keys)]))")
        end
        if !isempty(wrong_sup_keys)
            k = first(wrong_sup_keys)
            println("  - Incorrect #SUP in $(length(wrong_sup_keys)) itemset(s) (e.g., $(sort(collect(k))) -> SPMF=$(spmf_map[k]), Ours=$(ours_map[k]))")
        end
    end

    return VerificationResult(
        dataset, minsup, solver,
        length(spmf_map), length(ours_map),
        exact_matches, length(missing_keys), length(extra_keys),
        length(wrong_sup_keys), ours_dups, match_rate
    )
end

function run_solver_and_save!(solver_name::String, data_path::String, minsup::Real, out_path::String)
    println("  -> Running $solver_name on $(basename(data_path)) with minsup=$minsup...")
    txs = read_spmf_transactions(data_path)
    solver = solver_name == "Baseline" ? BaselineCharmSolver() : OptimizedCharmSolver()
    fit!(solver, txs, minsup)
    save_spmf(solver, out_path)
end

function main()
    test_cases = [
        ("mushrooms", 0.25, "25%", "Baseline",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "mushrooms.txt"),
         joinpath(@__DIR__, "expected", "spmf_mushrooms_25.txt"),
         joinpath(@__DIR__, "ours_mushrooms_25_base.txt")),
        ("mushrooms", 0.25, "25%", "Optimized",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "mushrooms.txt"),
         joinpath(@__DIR__, "expected", "spmf_mushrooms_25.txt"),
         joinpath(@__DIR__, "ours_mushrooms_25_opt.txt")),
        ("chess",     0.85, "85%", "Baseline",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "chess.txt"),
         joinpath(@__DIR__, "expected", "spmf_chess_85.txt"),
         joinpath(@__DIR__, "ours_chess_85_base.txt")),
        ("chess",     0.85, "85%", "Optimized",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "chess.txt"),
         joinpath(@__DIR__, "expected", "spmf_chess_85.txt"),
         joinpath(@__DIR__, "ours_chess_85_opt.txt")),
        ("accidents", 0.80, "80%", "Baseline",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "accidents.txt"),
         joinpath(@__DIR__, "expected", "spmf_accidents_80.txt"),
         joinpath(@__DIR__, "ours_accidents_80_base.txt")),
        ("accidents", 0.80, "80%", "Optimized",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "accidents.txt"),
         joinpath(@__DIR__, "expected", "spmf_accidents_80.txt"),
         joinpath(@__DIR__, "ours_accidents_80_opt.txt")),
        ("retail",    0.01, "1%",  "Baseline",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "retail.txt"),
         joinpath(@__DIR__, "expected", "spmf_retail_01.txt"),
         joinpath(@__DIR__, "ours_retail_01_base.txt")),
        ("retail",    0.01, "1%",  "Optimized",
         joinpath(@__DIR__, "..", "data", "benchmark", "origin", "retail.txt"),
         joinpath(@__DIR__, "expected", "spmf_retail_01.txt"),
         joinpath(@__DIR__, "ours_retail_01_opt.txt")),
    ]

    skip_regen = "--no-regen" in ARGS

    println("="^96)
    @printf("%-11s | %-6s | %-9s | %-9s | %-9s | %-9s | %-12s | %-10s\n",
            "Dataset", "MinSup", "Solver", "SPMF Cnt", "Ours Cnt", "Matched", "Discrepancy", "Match Rate")
    println("-"^96)

    for (ds, ms_val, ms_label, solver, data_f, spmf_f, ours_f) in test_cases
        if !isfile(spmf_f)
            @printf("%-11s | %-6s | %-9s | %-47s\n", ds, ms_label, solver, "[Expected SPMF file not found]")
            continue
        end

        # Tự động chạy lại solver nếu chưa có file ours_*
        if !skip_regen || !isfile(ours_f)
            if isfile(data_f)
                run_solver_and_save!(solver, data_f, ms_val, ours_f)
            else
                @printf("%-11s | %-6s | %-9s | %-47s\n", ds, ms_label, solver, "[Dataset not found: $data_f]")
                continue
            end
        end

        if !isfile(ours_f)
            @printf("%-11s | %-6s | %-9s | %-47s\n", ds, ms_label, solver, "[Output file not found: $ours_f]")
            continue
        end

        r = verify_pair(ds, ms_label, solver, spmf_f, ours_f)
        disc = r.missing_count + r.extra_count + r.wrong_sup_count + r.duplicate_count
        @printf("%-11s | %-6s | %-9s | %-9d | %-9d | %-9d | %-12d | %9.2f%%\n",
                r.dataset, r.minsup, r.solver, r.spmf_count, r.ours_count, r.exact_matches, disc, r.match_rate)
    end
    println("="^96)
end

main()
