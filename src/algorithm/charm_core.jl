function union_sorted(a::Vector{Int}, b::Vector{Int})::Vector{Int} # hàm gộp hai tidset Xi U Xj
    res = Int[]
    sizehint!(res, length(a) + length(b))
    i, j = 1, 1
    na, nb = length(a), length(b)
    @inbounds while i <= na && j <= nb
        va, vb = a[i], b[j]
        if va == vb
            push!(res, va)
            i += 1
            j += 1
        elseif va < vb 
            push!(res, va)
            i += 1
        else
            push!(res, vb)
            j += 1
        end
    end
    @inbounds while i <= na
        push!(res, a[i])
        i += 1
    end
    @inbounds while j <= nb
        push!(res, b[j])
        j += 1
    end
    return res
end

function is_strict_subset_items(a::Vector{Int}, b::Vector{Int})::Bool #kiểm tra a con b nhưng không bằng
    na, nb = length(a), length(b)
    na >= nb && return false
    i, j = 1, 1
    @inbounds while i <= na && j <= nb
        va, vb = a[i], b[j]
        if va == vb
            i += 1
            j += 1
        elseif va > vb
            j += 1
        else
            return false
        end
    end
    return i > na
end

function is_subsumed(solver::AbstractCharmSolver, items::Vector{Int}, tidset::AbstractTidset)::Bool #check xem tập có bị bao bởi tập khác không
    h = tid_hash(tidset) #đổi tidset thành mã hash
    candidates = get(solver.hash_table, h, nothing) #tìm trong dict nếu mà có mã hash bằng h thì trả về h không thì trả về nothing
    candidates === nothing && return false # nếu = nothing thì return false
    sup = length(tidset) 
    for (c_items, c_sup) in candidates
        if c_sup == sup && is_strict_subset_items(items, c_items) #nếu sup bằng nhau nhưng tập candidate bị bao bởi tập trong hash thì trả về true
            return true
        end
    end
    return false
end

function charm_extend!(solver::AbstractCharmSolver, P::Vector{CharmNode{T}}) where {T<:AbstractTidset} #P là lớp tương đương equivalence class
    i = 1
    while i <= length(P)
        Xi = P[i] #lấy tiền tố
        Pi = CharmNode{T}[] #khởi tạo để chứa các con sinh ra từ Xi
        j = i + 1

        while j <= length(P)
            Xj = P[j] 
            X = union_sorted(Xi.items, Xj.items) #tập item
            Y = tid_intersect(Xi.tidset, Xj.tidset) #tập tidset

            if length(Y) >= solver.minsup_count #check phổ biến
                if Xi.tidset == Xj.tidset #property 1
                    deleteat!(P, j) #xóa j
                    Xi.items = X #gộp Xi U Xj
                    for node in Pi
                        node.items = union_sorted(node.items, Xj.items) #thay lại các node bằng Xi U Xj trong nhánh đó
                    end
                elseif tid_issubset(Xi.tidset, Xj.tidset) #property 2
                    Xi.items = X
                    for node in Pi
                        node.items = union_sorted(node.items, Xj.items)  #thay lại các node bằng Xi U Xj trong nhánh đó
                    end
                    j += 1
                elseif tid_issubset(Xj.tidset, Xi.tidset) #property 3
                    deleteat!(P, j)
                    push!(Pi, CharmNode{T}(X, Y)) #thêm node mới
                else #property 4
                    push!(Pi, CharmNode{T}(X, Y)) 
                    j += 1
                end
            else
                j += 1
            end
        end

        !isempty(Pi) && charm_extend!(solver, Pi) 

        if !is_subsumed(solver, Xi.items, Xi.tidset) #check subsumption để add vào tập đóng
            sup = length(Xi.tidset)
            entry = (copy(Xi.items), sup) #tạo một bản sao Xi để không lỗi con trỏ
            push!(solver.closed_itemsets, entry) #thêm vào closed_itemset
            h = tid_hash(Xi.tidset)
            bucket = get!(solver.hash_table, h) do
                ClosedItemset[]
            end
            push!(bucket, entry) #đẩy entry vào hash
        end

        i += 1
    end
end


function fit!(solver::AbstractCharmSolver, transactions::Vector{Vector{Int}}, minsup::Real)
    empty!(solver.closed_itemsets) #clear tập đóng
    empty!(solver.hash_table) #clear hash_table

    num_tx = length(transactions)
    solver.num_transactions = num_tx
    solver.minsup_count = if isa(minsup, AbstractFloat) && 0.0 < minsup <= 1.0 
        ceil(Int, minsup * num_tx)
    else
        Int(minsup)
    end

    item_tids = Dict{Int, Vector{Int}}()
    for tid in 1:length(transactions)
        tx = transactions[tid]
        for item in tx
            if !haskey(item_tids, item)
                item_tids[item] = Int[]
            end

            tids = item_tids[item]
            if isempty(tids) || tids[end] != tid
                push!(tids, tid)
            end
        end
    end

    frequent_items = Int[]
    for (item, tids) in item_tids
        support = length(tids)
        if support >= solver.minsup_count
            push!(frequent_items, item)
        end
    end

    if isempty(frequent_items)
        return solver
    end

    T = typeof(create_tidset(solver, Int[], num_tx)) # kiểu tidset của solver (Vector / Bitset)
    P = CharmNode{T}[]
    for item in frequent_items
        push!(P, CharmNode{T}([item], create_tidset(solver, item_tids[item], num_tx)))
    end

    charm_extend!(solver, P)
    return solver
end