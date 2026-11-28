# Phân tích số liệu để giải thích kết quả benchmark và chứng minh hai hướng cải tiến.
#
#   julia --project=. scripts/analysis.jl
#
# 1) analysis_density.csv: đo kích thước các tidset thực sự được giao trong lúc khai thác, so với chiều rộng
#    bitset (n/64 từ 64 bit). Trả lời: vì sao bitset thắng ở dữ liệu dày nhưng không thắng ở dữ liệu thưa.
# 2) analysis_diffset.csv: so kích thước Tidset t(X) với Diffset d(XY) = t(X) \ t(Y). Trả lời: Diffset
#    có nhỏ hơn Tidset không, ở loại dữ liệu nào.

include(joinpath(@__DIR__, "..", "src", "interfaces.jl"))
include(joinpath(@__DIR__, "..", "src", "io_utils.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "baseline_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "optimized_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "charm_core.jl"))

const ROOT = dirname(@__DIR__)
const RESULTS = joinpath(ROOT, "results")
const PLAN = [("chess", "chess.txt", [0.7]), ("mushroom", "mushrooms.txt", [0.2]),
              ("retail", "retail.txt", [0.005, 0.001]), ("t10i4d100k", "T10I4D100K.txt", [0.005, 0.001])]

# ---------- 1) Đếm kích thước tidset trong các phép giao của CHARM ----------
# ProbeSolver chạy đúng thuật toán baseline, chỉ thêm bộ đếm vào tid_intersect.
struct ProbeTidset <: AbstractTidset
    v::VectorTidset
end

mutable struct ProbeSolver <: AbstractCharmSolver
    minsup_count::Int
    num_transactions::Int
    closed_itemsets::Vector{ClosedItemset}
    hash_table::Dict{Int64, Vector{ClosedItemset}}
end
ProbeSolver() = ProbeSolver(0, 0, ClosedItemset[], Dict{Int64, Vector{ClosedItemset}}())

const WORDS = Ref(1)            # số từ 64 bit của một bitset (= ceil(n/64))
const CALLS = Ref(0)            # số phép giao
const SUM_AB = Ref(0)           # tổng |a| + |b| (chi phí của phép giao dạng merge trên mảng)
const LT_WORDS = Ref(0)         # số phép giao có |a| + |b| < WORDS
const LT_8WORDS = Ref(0)        # số phép giao có |a| + |b| < 8 * WORDS

create_tidset(::ProbeSolver, tids::Vector{Int}, ::Int) = ProbeTidset(VectorTidset(tids))
Base.length(t::ProbeTidset) = length(t.v)
Base.:(==)(a::ProbeTidset, b::ProbeTidset) = a.v == b.v
tid_hash(t::ProbeTidset) = tid_hash(t.v)
tid_issubset(a::ProbeTidset, b::ProbeTidset) = tid_issubset(a.v, b.v)
function tid_intersect(a::ProbeTidset, b::ProbeTidset)::ProbeTidset
    ab = length(a) + length(b)
    CALLS[] += 1
    SUM_AB[] += ab
    ab < WORDS[] && (LT_WORDS[] += 1)
    ab < 8 * WORDS[] && (LT_8WORDS[] += 1)
    return ProbeTidset(tid_intersect(a.v, b.v))
end

function density_row(name, path, minsup)
    txs = read_spmf_transactions(path)
    n = length(txs)
    WORDS[] = cld(n, 64)
    CALLS[] = SUM_AB[] = LT_WORDS[] = LT_8WORDS[] = 0
    fit!(ProbeSolver(), txs, minsup)
    calls = max(CALLS[], 1)
    mean_ab = SUM_AB[] / calls
    return join([name, minsup, n, WORDS[], CALLS[], round(mean_ab, digits=1), round(mean_ab / WORDS[], digits=4),
                 round(LT_WORDS[] / calls, digits=4), round(LT_8WORDS[] / calls, digits=4)], ',')
end

# ---------- 2) Tidset so với Diffset ----------
# Với item X, Y (support σ): |t(XY)| = σ(XY), |d(XY)| = |t(X) \ t(Y)| = σ(X) - σ(XY).
# Diffset nhỏ hơn Tidset khi σ(XY) > σ(X)/2. Mức 1 (item đơn): d(X) = T \ t(X) có kích thước n - σ(X).
function diffset_row(name, path, minsup)
    txs = read_spmf_transactions(path)
    n = length(txs)
    mc = ceil(Int, minsup * n)
    item_tids = Dict{Int, Vector{Int}}()
    for (tid, tx) in enumerate(txs), item in tx
        push!(get!(item_tids, item, Int[]), tid)
    end
    items = sort([it for (it, t) in item_tids if length(t) >= mc]; by = it -> (length(item_tids[it]), it))
    bits = Dict(it => create_tidset(OptimizedCharmSolver(), item_tids[it], n) for it in items)
    item_small = count(it -> n - length(item_tids[it]) < length(item_tids[it]), items)
    pairs = 0; small = 0; sum_t = 0; sum_d = 0
    for a in 1:length(items), b in (a + 1):length(items)
        sxy = length(tid_intersect(bits[items[a]], bits[items[b]]))
        sxy >= mc || continue
        pairs += 1
        sum_t += sxy
        sum_d += length(item_tids[items[a]]) - sxy
        sxy > length(item_tids[items[a]]) / 2 && (small += 1)
    end
    p = max(pairs, 1)
    return join([name, minsup, n, length(items), round(item_small / max(length(items), 1), digits=4), pairs,
                 round(sum_t / p, digits=1), round(sum_d / p, digits=1), round(small / p, digits=4)], ',')
end

function main()
    mkpath(RESULTS)
    dens = ["dataset,minsup,n_tx,words,intersections,mean_ab,ratio,share_lt_words,share_lt_8words"]
    diff = ["dataset,minsup,n_tx,frequent_items,item_diffset_smaller,pairs,mean_tidset,mean_diffset,pair_diffset_smaller"]
    for (name, file, minsups) in PLAN, ms in minsups
        path = joinpath(ROOT, "data", "benchmark", "origin", file)
        isfile(path) || error("Thiếu $path (tải bằng scripts/load_dataset.jl)")
        push!(dens, density_row(name, path, ms)); (println(dens[end]); flush(stdout))
        push!(diff, diffset_row(name, path, ms)); (println(diff[end]); flush(stdout))
    end
    write(joinpath(RESULTS, "analysis_density.csv"), join(dens, '\n') * '\n')
    write(joinpath(RESULTS, "analysis_diffset.csv"), join(diff, '\n') * '\n')
    println("-> results/analysis_density.csv, results/analysis_diffset.csv")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
