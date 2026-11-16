"""
    read_spmf_transactions(filepath::AbstractString) -> Vector{Vector{Int}}

Read transactional data from an SPMF-formatted `.txt` file.
Each non-empty line represents one transaction of space-separated integer item IDs.
Duplicate items within a transaction are removed and items are sorted in ascending order.
"""
function read_spmf_transactions(filepath::AbstractString)::Vector{Vector{Int}}
    isfile(filepath) || error("FileNotFoundError: Input file does not exist at '$filepath'.")

    transactions = Vector{Int}[]
    open(filepath, "r") do io
        for (line_num, line) in enumerate(eachline(io))
            s = strip(line)
            # Skip blank lines, comments, and SPMF metadata headers
            (isempty(s) || startswith(s, "#") || startswith(s, "@")) && continue

            # Strip optional transaction utility/weight suffix after ':' if present
            tx_part = strip(first(split(s, ':')))
            isempty(tx_part) && continue

            items = Int[]
            for tok in split(tx_part)
                val = tryparse(Int, tok)
                val === nothing && error("ParseError: Invalid integer token '$tok' at line $line_num in '$filepath'.")
                push!(items, val)
            end

            sort!(items)
            unique!(items)
            !isempty(items) && push!(transactions, items)
        end
    end
    return transactions
end

"""
    save_spmf(solver::AbstractCharmSolver, filepath::AbstractString)

Export mined frequent closed itemsets stored in `solver.closed_itemsets` to `filepath`
using the standard SPMF output format: `<item1> <item2> ... #SUP: <support_count>`.
"""
function save_spmf(solver::AbstractCharmSolver, filepath::AbstractString)
    out_dir = dirname(filepath)
    !isempty(out_dir) && mkpath(out_dir)

    open(filepath, "w") do io
        for (items, sup) in solver.closed_itemsets
            sorted_items = issorted(items) ? items : sort(items)
            println(io, join(sorted_items, ' '), " #SUP: ", sup)
        end
    end
end