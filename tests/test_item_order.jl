using Test

include(joinpath(@__DIR__, "..", "src", "structures.jl"))
include(joinpath(@__DIR__, "..", "src", "interfaces.jl"))
include(joinpath(@__DIR__, "..", "src", "io_utils.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "baseline_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "optimized_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "charm_core.jl"))

closed_dict(s) = Dict(Set(items) => sup for (items, sup) in s.closed_itemsets)

@testset "Item order: thứ tự duyệt item không làm đổi tập kết quả" begin
    names = ["sample", "contextPasquier99", "contextZart", "contextItemsetTree", "contextRelim"]
    for name in names, minsup in (0.2, 0.4), Solver in (BaselineCharmSolver, OptimizedCharmSolver)
        txs = read_spmf_transactions(joinpath(@__DIR__, "..", "data", "toy", name * ".txt"))
        ref = Solver()
        fit!(ref, txs, minsup)
        for ord in (:support_asc, :support_desc)
            s = Solver()
            fit!(s, txs, minsup; order = ord)
            @test closed_dict(s) == closed_dict(ref)
        end
    end
    @test_throws ErrorException fit!(BaselineCharmSolver(), [[1, 2]], 1; order = :bad)
end
