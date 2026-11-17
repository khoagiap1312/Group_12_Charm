struct VectorTidset <: AbstractTidset
    tids::Vector{Int}
end

Base.length(ts::VectorTidset) = length(ts.tids) #trả về length của tid
Base.:(==)(a::VectorTidset, b::VectorTidset) = a.tids == b.tids #nạp chồng toán tử == 

tid_hash(ts::VectorTidset)::Int64 = isempty(ts.tids) ? 0 : sum(Int64, ts.tids)

function tid_intersect(a::VectorTidset, b::VectorTidset)::VectorTidset
    res = Int[]
    sizehint!(res, min(length(a), length(b)))
    i, j = 1, 1
    na, nb = length(a), length(b)
    @inbounds while i <= na && j <= nb
        va, vb = a.tids[i], b.tids[j]
        if va == vb
            push!(res, va) #lưu va vào kết quả res
            i += 1
            j += 1
        elseif va < vb #nếu không bằng thì tăng i lên cho bằng
            i += 1
        else
            j += 1 
        end
    end
    return VectorTidset(res)
end

function tid_issubset(a::VectorTidset, b::VectorTidset)::Bool #kiểm tra tập con
    na, nb = length(a), length(b)
    na > nb && return false
    i, j = 1, 1
    @inbounds while i <= na && j <= nb 
        va, vb = a.tids[i], b.tids[j]
        if va == vb
            i += 1
            j += 1
        elseif va > vb
            j += 1
        else #va<vb
            return false #vì đã nhỏ hơn thì b càng tăng thì cũng không xuất hiện a nên return false
        end
    end
    if (i>na)
        return true
    end
    return false
end

mutable struct BaselineCharmSolver <: AbstractCharmSolver
    minsup_count::Int
    num_transactions::Int
    closed_itemsets::Vector{ClosedItemset}
    hash_table::Dict{Int64, Vector{ClosedItemset}}
end

BaselineCharmSolver() = BaselineCharmSolver(0, 0, ClosedItemset[], Dict{Int64, Vector{ClosedItemset}}()) #khởi tạo minsip,số transaction,tập closed, và khởi tạo mảng băm

create_tidset(::BaselineCharmSolver, tids::Vector{Int}, ::Int) = VectorTidset(tids) #tạo tidset