using Test

include(joinpath(@__DIR__, "..", "src", "interfaces.jl"))
include(joinpath(@__DIR__, "..", "src", "io_utils.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "baseline_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "optimized_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "charm_core.jl"))

@testset verbose=true "Unit test for baseline" begin

   
    #baseline_solver.jl
    @testset verbose=true "VectorTidset & Solver" begin
        
        # 1.1 Test Base.length & Base.:(==)
        @testset "length & ==" begin
            ts_empty = VectorTidset(Int[])
            ts1 = VectorTidset([1, 3, 5])
            ts2 = VectorTidset([1, 3, 5])
            ts3 = VectorTidset([1, 3, 6])

            @test length(ts_empty) == 0
            @test length(ts1) == 3
            @test ts1 == ts2
            @test ts1 != ts3
            @test ts1 != ts_empty
        end

        # 1.2 Test tid_hash
        @testset "tid_hash" begin
            @test tid_hash(VectorTidset(Int[])) == 0
            @test tid_hash(VectorTidset([1, 2, 4])) == 7       # 1 + 2 + 4 = 7
            @test tid_hash(VectorTidset([10, 20, 30])) == 60   # 10 + 20 + 30 = 60
        end

        # 1.3 Test tid_intersect
        @testset "tid_intersect" begin
            a = VectorTidset([1, 3, 5, 7, 9])
            b = VectorTidset([2, 3, 6, 7, 10])
            c = VectorTidset([11, 12])
            empty_ts = VectorTidset(Int[])

            # Giao có phần tử chung
            @test tid_intersect(a, b) == VectorTidset([3, 7])
            # Giao không có phần tử chung (rời rạc)
            @test tid_intersect(a, c) == empty_ts
            # Giao với tập rỗng
            @test tid_intersect(a, empty_ts) == empty_ts
            # Giao với chính nó
            @test tid_intersect(a, a) == a
        end

        # 1.4 Test tid_issubset
        @testset "tid_issubset" begin
            sub = VectorTidset([2, 4])
            parent = VectorTidset([1, 2, 3, 4, 5])
            other = VectorTidset([2, 4, 6])
            empty_ts = VectorTidset(Int[])

            @test tid_issubset(sub, parent) == true       # [2,4] con của [1,2,3,4,5]
            @test tid_issubset(parent, sub) == false      # Tập to không là con tập nhỏ
            @test tid_issubset(sub, sub) == true          # Tập con chính nó
            @test tid_issubset(other, parent) == false    # Có phần tử 6 không thuộc parent
            @test tid_issubset(empty_ts, parent) == true  # Tập rỗng là con mọi tập
        end

        # 1.5 Test Constructor & create_tidset
        @testset "BaselineCharmSolver & create_tidset" begin
            solver = BaselineCharmSolver()
            @test solver.minsup_count == 0
            @test solver.num_transactions == 0
            @test isempty(solver.closed_itemsets)
            @test isempty(solver.hash_table)

            ts = create_tidset(solver, [1, 5, 8], 10)
            @test isa(ts, VectorTidset)
            @test ts == VectorTidset([1, 5, 8])
        end
    end

    #charm_core.jl
    @testset verbose=true "Core Operations & CHARM property" begin

        # 2.1 Test union_sorted
        @testset "union_sorted" begin
            @test union_sorted([1, 3, 5], [2, 3, 4]) == [1, 2, 3, 4, 5]
            @test union_sorted([1, 2], [3, 4]) == [1, 2, 3, 4]          # Rời rạc
            @test union_sorted([1, 2], [1, 2]) == [1, 2]                # Bằng nhau
            @test union_sorted(Int[], [1, 2]) == [1, 2]                 # Hợp với rỗng
            @test union_sorted(Int[], Int[]) == Int[]                   # Cả 2 rỗng
        end

        # 2.2 Test is_strict_subset_items
        @testset "is_strict_subset_items" begin
            @test is_strict_subset_items([1, 3], [1, 2, 3]) == true     # Tập con thật sự
            @test is_strict_subset_items([1, 2], [1, 2]) == false       # không phải strict
            @test is_strict_subset_items([1, 2, 3], [1, 2]) == false    # Dài hơn => không phải con
            @test is_strict_subset_items([1, 4], [1, 2, 3]) == false    # Khác phần tử
            @test is_strict_subset_items(Int[], [1]) == true            # Rỗng là strict subset của [1]
        end

        # 2.3 Test is_subsumed
        @testset "is_subsumed" begin
            solver = BaselineCharmSolver()
            # Đưa vào hash table một tập đóng candidate: [1, 2, 3] với support=4
            h = tid_hash(VectorTidset([1, 2, 3, 4])) # hash = 10
            solver.hash_table[h] = [([1, 2, 3], 4)]

            # Tập [1, 2] có cùng support=4 và cùng mã băm => Bị subsumed bởi [1, 2, 3]
            @test is_subsumed(solver, [1, 2], VectorTidset([1, 2, 3, 4])) == true

            # Tập [1, 2] nhưng support=3 (khác support) => Không bị subsumed
            @test is_subsumed(solver, [1, 2], VectorTidset([1, 2, 3])) == false

            # Tập [1, 4] có cùng sup=4 nhưng không phải tập con của [1, 2, 3] => Không bị subsumed
            @test is_subsumed(solver, [1, 4], VectorTidset([1, 2, 3, 4])) == false
        end

        # 2.4 Test 4 tính chất trong charm_extend!
        @testset "charm_extend!" begin
            # Property 1: t(Xi) == t(Xj) => Gộp Xi U Xj, xóa Xj
            solver1 = BaselineCharmSolver()
            solver1.minsup_count = 2
            P1 = [
                CharmNode([1], VectorTidset([1, 2])),
                CharmNode([2], VectorTidset([1, 2]))
            ]
            charm_extend!(solver1, P1)
            # Kết quả: Gộp thành đúng 1 tập [1, 2] duy nhất
            @test length(solver1.closed_itemsets) == 1
            @test solver1.closed_itemsets[1][1] == [1, 2]
            @test solver1.closed_itemsets[1][2] == 2

            # Property 2: t(Xi) ⊂ t(Xj) => Xi = Xi U Xj, giữ Xj
            solver2 = BaselineCharmSolver()
            solver2.minsup_count = 2
            P2 = [
                CharmNode([1], VectorTidset([1, 2])),
                CharmNode([2], VectorTidset([1, 2, 3]))
            ]
            charm_extend!(solver2, P2)
            # Sinh ra tập [1, 2] (#SUP: 2) và tập [2] (#SUP: 3)
            res2 = Dict(sort(k) => v for (k, v) in solver2.closed_itemsets)
            @test res2[[1, 2]] == 2
            @test res2[[2]] == 3

            # Property 4: t(Xi) != t(Xj) nhưng giao thỏa minsup => sinh nhánh con Pi
            solver4 = BaselineCharmSolver()
            solver4.minsup_count = 2
            P4 = [
                CharmNode([1], VectorTidset([1, 2, 3])),
                CharmNode([2], VectorTidset([2, 3, 4]))
            ]
            charm_extend!(solver4, P4)
            # Sinh ra tập con giao [1, 2] (#SUP: 2), và 2 tập gốc [1] (#SUP: 3), [2] (#SUP: 3)
            res4 = Dict(sort(k) => v for (k, v) in solver4.closed_itemsets)
            @test res4[[1, 2]] == 2
            @test res4[[1]] == 3
            @test res4[[2]] == 3
        end

        #fit! Xử lý ngưỡng minsup & Dữ liệu
        @testset "fit!" begin
            solver = BaselineCharmSolver()
            txs = [[1, 2], [2, 3], [1, 2, 3]] # 3 giao dịch

            # Kiểm tra minsup tương đối (float) -> ceil(0.5 * 3) = 2
            fit!(solver, txs, 0.5)
            @test solver.minsup_count == 2
            @test solver.num_transactions == 3

            # Kiểm tra minsup tuyệt đối (int)
            fit!(solver, txs, 3)
            @test solver.minsup_count == 3

            # Dữ liệu không có item nào đạt minsup
            fit!(solver, txs, 10)
            @test isempty(solver.closed_itemsets)
        end
    end
end

   @testset verbose=true "BitsetTidset & Optimized Solver" begin
        # Helper tạo BitsetTidset nhanh cho test
        function make_bitset(tids::Vector{Int}, num_tx::Int=10)
            bits = falses(num_tx)
            for t in tids
                bits[t] = true
            end
            return BitsetTidset(bits, length(tids))
        end
        # 3.1 Test Constructor & create_tidset
        @testset "Constructor & create_tidset" begin
            solver = OptimizedCharmSolver()
            @test solver.minsup_count == 0
            @test solver.num_transactions == 0
            @test isempty(solver.closed_itemsets)
            @test isempty(solver.hash_table)
            num_tx = 100
            ts = create_tidset(solver, [1, 5, 8, 65], num_tx)
            @test isa(ts, BitsetTidset)
            @test length(ts) == 4
            @test ts.bits[1] == true
            @test ts.bits[5] == true
            @test ts.bits[8] == true
            @test ts.bits[65] == true
            @test ts.bits[2] == false
        end
        # 3.2 Test Base.length & Base.:(==)
        @testset "length & ==" begin
            ts_empty = make_bitset(Int[])
            ts1 = make_bitset([1, 3, 5])
            ts2 = make_bitset([1, 3, 5])
            ts3 = make_bitset([1, 3, 6])
            @test length(ts_empty) == 0
            @test length(ts1) == 3
            @test ts1 == ts2
            @test ts1 != ts3
            @test ts1 != ts_empty
        end
        # 3.3 Test tid_hash
        @testset "tid_hash" begin
            ts1 = make_bitset([1, 2, 4])
            ts2 = make_bitset([1, 2, 4])
            ts3 = make_bitset([1, 2, 5])
            @test isa(tid_hash(ts1), Int64)
            @test tid_hash(ts1) == tid_hash(ts2)  # Cùng tidset phải cùng mã băm
            @test tid_hash(ts1) != tid_hash(ts3)  # Khác tidset thì băm khác
        end
        # 3.4 Test tid_intersect
        @testset "tid_intersect" begin
            num_tx = 100 # Test vượt ngưỡng 64 bit (2 chunks) để đảm bảo bitwise đa chunk hoạt động chuẩn
            a = make_bitset([1, 3, 5, 65, 80], num_tx)
            b = make_bitset([2, 3, 6, 65, 90], num_tx)
            c = make_bitset([11, 12], num_tx)
            empty_ts = make_bitset(Int[], num_tx)
            # Giao có phần tử chung (bao gồm cả chunk thứ 2 là 65)
            @test tid_intersect(a, b) == make_bitset([3, 65], num_tx)
            @test length(tid_intersect(a, b)) == 2
            # Giao rời rạc
            @test tid_intersect(a, c) == empty_ts
            @test length(tid_intersect(a, c)) == 0
            # Giao với rỗng và giao với chính nó
            @test tid_intersect(a, empty_ts) == empty_ts
            @test tid_intersect(a, a) == a
        end
        # 3.5 Test tid_issubset
        @testset "tid_issubset" begin
            num_tx = 100
            sub = make_bitset([2, 65], num_tx)
            parent = make_bitset([1, 2, 3, 65, 80], num_tx)
            other = make_bitset([2, 65, 99], num_tx)
            empty_ts = make_bitset(Int[], num_tx)
            @test tid_issubset(sub, parent) == true
            @test tid_issubset(parent, sub) == false
            @test tid_issubset(sub, sub) == true
            @test tid_issubset(other, parent) == false
            @test tid_issubset(empty_ts, parent) == true
        end
        # 3.6 Test fit! so khớp với Baseline trên dữ liệu mock
        @testset "Cross-check fit! Baseline vs Optimized" begin
            txs = [
                [1, 2, 4, 5],
                [2, 3, 5],
                [1, 2, 4, 5],
                [1, 2, 3, 5],
                [1, 2, 3, 4, 5],
                [2, 3, 4]
            ]
            for ms in [0.5, 0.33, 2, 3]
                base_solver = BaselineCharmSolver()
                opt_solver  = OptimizedCharmSolver()
                fit!(base_solver, txs, ms)
                fit!(opt_solver, txs, ms)
                d_base = Dict(sort(k) => v for (k, v) in base_solver.closed_itemsets)
                d_opt  = Dict(sort(k) => v for (k, v) in opt_solver.closed_itemsets)
                @test d_base == d_opt
            end
        end
    end