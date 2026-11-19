# Optimized CHARM: tidset = bitset (BitVector chunks + cached popcount).
# Thuật toán lõi (charm_core.jl) dùng chung với baseline, chỉ đổi biểu diễn tidset.

struct BitsetTidset <: AbstractTidset
    bits::BitVector
    cnt::Int # support, cache để length() là O(1)
end

Base.length(ts::BitsetTidset) = ts.cnt
Base.:(==)(a::BitsetTidset, b::BitsetTidset) = a.cnt == b.cnt && a.bits.chunks == b.bits.chunks

# Chunk cuối của BitVector luôn có padding bằng 0 nên hash/so sánh chunks là an toàn.
tid_hash(ts::BitsetTidset)::Int64 = reinterpret(Int64, hash(ts.bits.chunks))

function tid_intersect(a::BitsetTidset, b::BitsetTidset)::BitsetTidset
    res = BitVector(undef, length(a.bits))
    ca, cb, cr = a.bits.chunks, b.bits.chunks, res.chunks
    n = 0
    @inbounds @simd for k in eachindex(ca)
        w = ca[k] & cb[k]
        cr[k] = w
        n += count_ones(w)
    end
    return BitsetTidset(res, n)
end

function tid_issubset(a::BitsetTidset, b::BitsetTidset)::Bool
    a.cnt > b.cnt && return false
    ca, cb = a.bits.chunks, b.bits.chunks
    n, k = length(ca), 1
    @inbounds while k <= n # @simd không cho thoát sớm: vector hóa theo khối 8 từ, thoát sớm giữa các khối
        hi = min(k + 7, n)
        acc = UInt64(0)
        @simd for j in k:hi
            acc |= ca[j] & ~cb[j]
        end
        acc != 0 && return false
        k = hi + 1
    end
    return true
end

mutable struct OptimizedCharmSolver <: AbstractCharmSolver
    minsup_count::Int
    num_transactions::Int
    closed_itemsets::Vector{ClosedItemset}
    hash_table::Dict{Int64, Vector{ClosedItemset}}
end

OptimizedCharmSolver() = OptimizedCharmSolver(0, 0, ClosedItemset[], Dict{Int64, Vector{ClosedItemset}}())

function create_tidset(::OptimizedCharmSolver, tids::Vector{Int}, num_tx::Int)
    bits = falses(num_tx)
    @inbounds for t in tids
        bits[t] = true
    end
    return BitsetTidset(bits, length(tids))
end
