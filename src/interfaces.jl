# ABSTRACT CLASSES (INTERFACES)

"""
    AbstractTidset
Base interface for vertical transaction ID (TID) set representations.
Concrete subtypes must also implement `Base.length(ts)` and `Base.:(==)(a, b)`.
"""
abstract type AbstractTidset end

"""
    AbstractCharmSolver
Base interface for CHARM algorithm solvers.
Concrete subtypes must maintain the following fields:
  - `minsup_count::Int`
  - `num_transactions::Int`
  - `closed_itemsets::Vector{ClosedItemset}`
  - `hash_table::Dict{Int64, Vector{ClosedItemset}}`
"""
abstract type AbstractCharmSolver end

# SHARED DATA STRUCTURES

const ClosedItemset = Tuple{Vector{Int}, Int} # (sorted_items, support_count)

mutable struct CharmNode{T<:AbstractTidset}
    items::Vector{Int}
    tidset::T
end

# TIDSET INTERFACE METHODS (TO BE IMPLEMENTED BY TIDSET SUBTYPES)

function tid_intersect(a::T, b::T)::T where {T<:AbstractTidset}
    error("NotImplementedError: tid_intersect() is not implemented for $(T).")
end

function tid_issubset(a::T, b::T)::Bool where {T<:AbstractTidset}
    error("NotImplementedError: tid_issubset() is not implemented for $(T).")
end

function tid_hash(ts::AbstractTidset)::Int64
    error("NotImplementedError: tid_hash() is not implemented for $(typeof(ts)).")
end

# SOLVER INTERFACE METHODS

# Factory method to be overridden by each concrete Solver subclass
function create_tidset(solver::AbstractCharmSolver, tids::Vector{Int}, num_tx::Int)::AbstractTidset
    error("NotImplementedError: create_tidset() is not implemented for $(typeof(solver)).")
end

# Core algorithm & I/O signatures (implemented in charm_core.jl & io_utils.jl)
function fit!(solver::AbstractCharmSolver, transactions::Vector{Vector{Int}}, minsup::Real) end
function read_spmf_transactions(filepath::AbstractString)::Vector{Vector{Int}} end
function save_spmf(solver::AbstractCharmSolver, filepath::AbstractString) end