using Test

include(joinpath(@__DIR__, "..", "src", "structures.jl"))
include(joinpath(@__DIR__, "..", "src", "interfaces.jl"))
include(joinpath(@__DIR__, "..", "src", "io_utils.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "baseline_solver.jl"))
# include(joinpath(@__DIR__, "..", "src", "algorithm", "optimized_solver.jl"))
include(joinpath(@__DIR__, "..", "src", "algorithm", "charm_core.jl"))

function parse_spmf_output(filepath::AbstractString)::Dict{Vector{Int}, Int}
    result = Dict{Vector{Int}, Int}()
    open(filepath, "r") do io
        for line in eachline(io)
            s = strip(line)
            (isempty(s) || startswith(s, "@") || !occursin("#SUP:", s)) && continue
            
            parts = split(s, "#SUP:")
            items = sort!([parse(Int, tok) for tok in split(strip(parts[1]))])
            sup = parse(Int, strip(parts[2]))
            result[items] = sup
        endSS
    end
    return result
end

function to_dict(solver::AbstractCharmSolver)::Dict{Vector{Int}, Int}
    return Dict(sort(items) => sup for (items, sup) in solver.closed_itemsets)
end

@testset "Group 12 CHARM - Automated Test Suite" begin
    sample_path = joinpath(@__DIR__, "..", "data", "toy", "sample.txt")
    transactions = read_spmf_transactions(sample_path)

    @testset "1. Low-Level Set & Tidset Operations" begin
        t1 = VectorTidset([1, 3, 4, 5])
        t2 = VectorTidset([2, 3, 5, 6])
        t_sub = VectorTidset([3, 5])

        @test length(t1) == 4
        @test tid_intersect(t1, t2) == VectorTidset([3, 5])
        @test tid_intersect(t1, VectorTidset(Int[])) == VectorTidset(Int[])
        @test tid_issubset(t_sub, t1) == true
        @test tid_issubset(t1, t_sub) == false
        @test tid_issubset(t1, t1) == true
        @test tid_hash(t1) == 13

        @test union_sorted([1, 3, 5], [2, 3, 4]) == [1, 2, 3, 4, 5]
        @test is_strict_subset_items([1, 5], [1, 2, 5]) == true
        @test is_strict_subset_items([1, 5], [1, 5]) == false
    end

    @testset "2. Edge Cases & SPMF I/O Roundtrip" begin
        solver_high = BaselineCharmSolver()
        fit!(solver_high, transactions, 10)
        @test isempty(solver_high.closed_itemsets)

        solver_min = BaselineCharmSolver()
        fit!(solver_min, transactions, 1)
        @test length(solver_min.closed_itemsets) == 10

        tmp_in = tempname() * ".txt"
        write(tmp_in, "# comment line\n1 2 2 4 5\n\n2 3 5\n")
        parsed_tx = read_spmf_transactions(tmp_in)
        @test parsed_tx == [[1, 2, 4, 5], [2, 3, 5]]
        rm(tmp_in, force=true)

        tmp_out = tempname() * ".txt"
        save_spmf(solver_min, tmp_out)
        @test parse_spmf_output(tmp_out) == to_dict(solver_min)
        rm(tmp_out, force=true)
    end

    @testset "3. Ground Truth Verification (Zaki 2002)" begin
        solver = BaselineCharmSolver()
        fit!(solver, transactions, 0.5)
        expected = Dict{Vector{Int}, Int}(
            [2]          => 6,
            [2, 5]       => 5,
            [1, 2, 5]    => 4,
            [2, 3]       => 4,
            [2, 4]       => 4,
            [1, 2, 4, 5] => 3,
            [2, 3, 5]    => 3
        )
        @test to_dict(solver) == expected

        spmf_jar = joinpath(@__DIR__, "spmf.jar")
        if isfile(spmf_jar) && Sys.which("java") !== nothing
            for (rel_sup, spmf_pct) in [(0.5, "50%"), (0.333, "33.3%"), (0.1, "10%")]
                spmf_out = tempname() * ".txt"
                run(`java -jar $spmf_jar run Charm_bitset $sample_path $spmf_out $spmf_pct`)
                fit!(solver, transactions, rel_sup)
                @test to_dict(solver) == parse_spmf_output(spmf_out)
                rm(spmf_out, force=true)
            end
        end
    end

    if @isdefined(OptimizedCharmSolver)
        @testset "4. Cross-Check: Baseline vs Optimized Solver" begin
            base_solver = BaselineCharmSolver()
            opt_solver  = OptimizedCharmSolver()
            for sup in [0.8, 0.5, 0.3, 1]
                fit!(base_solver, transactions, sup)
                fit!(opt_solver, transactions, sup)
                @test to_dict(base_solver) == to_dict(opt_solver)
            end
        end
    end
end