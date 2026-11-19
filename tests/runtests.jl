using Test

@testset verbose=true "Group 12 CHARM - Full Test Suite" begin
    println("\n=======================================================")
    println(">>> Running Unit Tests & Edge Cases...")
    println("=======================================================")
    include(joinpath(@__DIR__, "test_unit.jl"))

    println("\n=======================================================")
    println(">>> Running Automated Correctness Tests vs SPMF...")
    println("=======================================================")
    include(joinpath(@__DIR__, "test_correctness.jl"))
end
