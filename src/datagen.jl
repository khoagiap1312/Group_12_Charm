using StableRNGs
using Random

# 1. Tạo tập con theo scaleability

abstract type SamplingStrategy end
struct PrefixSampling <: SamplingStrategy end
struct RandomSampling <: SamplingStrategy
    seed::Int
end

subset_size(n::Integer, pct::Integer) = round(Int, n * pct / 100)

# Tối ưu cho PrefixSampling: không cần tạo generator
function select_mask(::PrefixSampling, n::Integer, k::Integer)
    mask = falses(n)
    mask[1:k] .= true
    return mask
end

function select_mask(s::RandomSampling, n::Integer, k::Integer)
    mask = falses(n)
    perm = randperm(StableRNG(s.seed), n)
    mask[@view perm[1:k]] .= true
    return mask
end


function generate_scalability_subset(input_path::AbstractString, pct::Integer,
        strategy::SamplingStrategy = RandomSampling(0);
        out_root::AbstractString = "data/scale")
    # Mặc định: file đã chạy check_spmf đúng định dạng
    n = countlines(input_path)                          # Pass 1
    k = subset_size(n, pct)
    mask = select_mask(strategy, n, k)

    base, ext = splitext(basename(input_path))
    out_dir = joinpath(out_root, "$(pct)_percentage")
    mkpath(out_dir)
    output_path = joinpath(out_dir, "$(base)_$(pct)$(ext)")

    open(output_path, "w") do io                        # Pass 2 (streaming)
        for (line, keep) in zip(eachline(input_path), mask)
            keep && println(io, line)
        end
    end
    return output_path, count(mask)
end

# 2. Theo độ dài Transaction


"""
Cấu hình sinh dữ liệu tổng hợp chuẩn T{avg_len}I{avg_pat_len}D{n_trans}
Chuẩn Synthetic theo kiểu IBM Quest: T{T}_I{I}_D{N}
"""

struct SyntheticFIMConfig
    n_trans::Int        # số giao dịch (cố định)
    n_items::Int        # số item (cố định)
    n_patterns::Int     # số pattern tiềm ẩn
    avg_pat_len::Int    # độ dài trung bình pattern |I|
    seed::Int           # seed gốc

    function SyntheticFIMConfig(n_trans, n_items, n_patterns, avg_pat_len, seed)
        n_trans >= 1     || throw(ArgumentError("n_trans phải >= 1"))
        n_items >= 2     || throw(ArgumentError("n_items phải >= 2 để tạo được itemset"))
        n_patterns >= 1  || throw(ArgumentError("n_patterns phải >= 1"))
        avg_pat_len >= 1 || throw(ArgumentError("avg_pat_len phải >= 1"))
        new(n_trans, n_items, n_patterns, avg_pat_len, seed)
    end
end

@inline function rand_poisson(rng::AbstractRNG, lambda::Real)
    L = exp(-Float64(lambda))
    k = 0
    p = 1.0
    while p > L
        k += 1
        p *= rand(rng)
    end
    return max(1, k - 1)
end


function pick_random_patterns(n_patterns::Int, avg_pat_len::Int, n_items::Int, seed::Int = 0)
    rng = StableRNG(seed)
    
    patterns = Vector{Vector{Int}}(undef, n_patterns) # n_patterns gồm pattern có độ dài random theo avg_pat_len
    picked = BitSet()
    
    max_pat_len = min(10, n_items)
    min_path_len = min(2, max_pat_len)

    for i in 1:n_patterns
        pattern_size = clamp(rand_poisson(rng, avg_pat_len), min_path_len, max_pat_len)


        while length(picked) < pattern_size
            push!(picked, rand(rng, 1: n_items))
        end

        # collect biến BitSet thành Vector{Int}
        patterns[i] = collect(picked)
    end

    # Mỗi patterns có xác suất chọn theo phân phối mũ e^1
    weights = [randexp(rng) for _ in 1:n_patterns]
    cum_weights = cumsum(weights)
    return patterns, cum_weights
end

function build_one_transaction!(
    buf::BitSet, rng:: AbstractRNG,
    patterns::Vector{Vector{Int}}, cum_weights::Vector{Float64}, 
    T::Int, n_items::Int)

    empty!(buf)

    target_len = clamp(rand_poisson(rng, T), 1, n_items)
    total_w = cum_weights[end]

    while length(buf) < target_len
        
        r = rand(rng) * total_w
        
        pat_idx = searchsortedfirst(cum_weights, r)
        picked_pattern = patterns[pat_idx]

        for item in picked_pattern
            push!(buf, item)

            if length(buf) >= target_len
                break
            end
        end
    end
    return buf
end


function generate_synthetic_length_dataset(
    T::Int,
    cfg::SyntheticFIMConfig,
    out_root::AbstractString = "data/benchmark/length")

    # Tạo danh sách patterns và trọng số cố định theo seed
    patterns, cum_weights = pick_random_patterns(cfg.n_patterns, cfg.avg_pat_len, cfg.n_items, cfg.seed)

    # Tính tổng số item thực tế có trong hồ pattern để tránh treo vòng lặp while
    max_possible_len = length( reduce(union!, patterns; init=BitSet()) )

    out_dir = joinpath(out_root, "$(T)_length")
    mkpath(out_dir)
    output_path = joinpath(out_dir, "syn_T$(T)_I$(cfg.avg_pat_len)_D$(cfg.n_trans).txt")

    open(output_path, "w") do file
        buf = BitSet()
        trans_rng = StableRNG(cfg.seed + T)

        for _ in 1:cfg.n_trans
            build_one_transaction!(buf, trans_rng, patterns,cum_weights, T, max_possible_len)
            join(file, buf, ' ')
            println(file)
        end
    end

    return output_path
end

CFG = SyntheticFIMConfig(20_000, 1_000, 200, 4, 0)