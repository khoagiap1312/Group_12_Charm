abstract type AbstractTidset end
abstract type AbstractCharmSolver end

const ClosedItemset = Tuple{Vector{Int}, Int} #(các items, support)

mutable struct CharmNode{T<:AbstractTidset}
    items::Vector{Int}
    tidset::T
end

function tid_intersect(a::T, b::T)::T where {T<:AbstractTidset}
    error("NotImplementedError: tid_intersect() is not implemented for $(T).")
end

function tid_issubset(a::T, b::T)::Bool where {T<:AbstractTidset}
    error("NotImplementedError: tid_issubset() is not implemented for $(T).")
end

function tid_hash(ts::AbstractTidset)::Int64
    error("NotImplementedError: tid_hash() is not implemented for $(typeof(ts)).")
end

function create_tidset(solver::AbstractCharmSolver, tids::Vector{Int}, num_tx::Int)::AbstractTidset
    error("NotImplementedError: create_tidset() is not implemented for $(typeof(solver)).")
end

function fit! end
function read_spmf_transactions end
function save_spmf end