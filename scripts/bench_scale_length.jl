# Benchmark Scalability (10%–100%) và Ảnh hưởng độ dài giao dịch (10–40)
# Tái sử dụng trực tiếp hàm đo `run_once`, `med`, `fmt` từ scripts/benchmark.jl
# (không sửa scripts/benchmark.jl để tránh conflict Git).
#
# Cách đặt file:
#   scripts/bench_scale_length.jl
#
# Cách chạy (từ thư mục gốc repo Group_12_Charm):
#   1) Kiểm tra dữ liệu & xuất bảng thống kê:
#        julia scripts/bench_scale_length.jl stats retail
#        julia scripts/bench_scale_length.jl stats accidents
#
#   2) Chạy Scalability (10/25/50/75/100%) ở 1–2 mức minsup cố định:
#        julia scripts/bench_scale_length.jl scale retail 0.005 0.001 --repeat 3 --timeout 120
#        julia scripts/bench_scale_length.jl scale accidents 0.4 0.3 --repeat 3 --timeout 120
#
#   3) Chạy Ảnh hưởng độ dài giao dịch (10/15/20/25/30/35/40) ở minsup cố định:
#        julia scripts/bench_scale_length.jl length 0.01 --repeat 3 --timeout 120
#
#   Tùy chọn thêm:
#        --repeat N                     Số lần lặp mỗi cấu hình lấy trung vị (mặc định: 3)
#        --timeout S                    Giới hạn thời gian mỗi lần chạy tính bằng giây (mặc định: 120)
#        --engines spmf,baseline,optimized   Chọn engine cần chạy (mặc định: cả 3)
#        --skip-preflight               Bỏ qua kiểm tra tương thích src/main.jl

include(joinpath(@__DIR__, "benchmark.jl"))

const SCALE_DATASETS = Dict(
    "accidents"  => "accidents",
    "chess"      => "chess",
    "mushroom"   => "mushrooms",
    "mushrooms"  => "mushrooms",
    "retail"     => "retail",
    "t10i4d100k" => "T10I4D100K",
)

const SCALE_LEVELS  = [10, 25, 50, 75, 100]
const LENGTH_LEVELS = [10, 15, 20, 25, 30, 35, 40]

const SCALE_RAW_HEAD = "dataset,scale_pct,n_trans,avg_len,minsup,engine,run,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"
const SCALE_SUM_HEAD = "dataset,scale_pct,n_trans,avg_len,minsup,engine,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"

const LENGTH_RAW_HEAD = "dataset,target_len,n_trans,avg_len,minsup,engine,run,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"
const LENGTH_SUM_HEAD = "dataset,target_len,n_trans,avg_len,minsup,engine,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"

const STATS_HEAD = "group,label,file,n_trans,n_items,avg_len,min_len,max_len,dup_lines,empty_lines"

# ---------------------------------------------------------------------------
# Kiểm tra tiền điều kiện & thống kê file SPMF
# ---------------------------------------------------------------------------

function preflight_check(engines::Vector{String})
    ok = true
    if "spmf" in engines && !isfile(JAR)
        println(stderr, "[LỖI] Không tìm thấy SPMF jar tại: $JAR")
        ok = false
    end
    if ("baseline" in engines || "optimized" in engines)
        if !isfile(MAIN)
            println(stderr, "[LỖI] Không tìm thấy $MAIN")
            ok = false
        else
            src = read(MAIN, String)
            if !(occursin("\"-w\"", src) || occursin("--warmup", src))
                println(stderr, "[LỖI] src/main.jl hiện tại CHƯA hỗ trợ cờ -w / --warmup như scripts/benchmark.jl yêu cầu.")
                println(stderr, "      Hãy git pull bản src/main.jl mới nhất trước khi chạy.")
                ok = false
            end
            if !occursin("Total:", src)
                println(stderr, "[CẢNH BÁO] src/main.jl chưa in 'Total: ... ms' -> cột time_ms của Julia sẽ bị trống.")
            end
        end
    end
    return ok
end

function inspect_spmf_file(path::AbstractString)
    n_trans = 0
    total_items = 0
    min_len = typemax(Int)
    max_len = 0
    unique_items = Set{Int}()
    dup_lines = 0
    empty_lines = 0

    for line in eachline(path)
        s = strip(line)
        if isempty(s)
            empty_lines += 1
            continue
        end
        (startswith(s, '@') || startswith(s, '#') || startswith(s, '%')) && continue
        items = parse.(Int, split(s))
        len = length(items)
        if length(Set(items)) != len
            dup_lines += 1
        end
        n_trans += 1
        total_items += len
        len < min_len && (min_len = len)
        len > max_len && (max_len = len)
        union!(unique_items, items)
    end

    avg_len = n_trans > 0 ? round(total_items / n_trans; digits=2) : 0.0
    min_len = n_trans > 0 ? min_len : 0
    return (
        n_trans = n_trans,
        n_items = length(unique_items),
        avg_len = avg_len,
        min_len = min_len,
        max_len = max_len,
        dup_lines = dup_lines,
        empty_lines = empty_lines,
    )
end

function scale_file_path(dataset_key::AbstractString, pct::Int)::String
    prefix = SCALE_DATASETS[lowercase(dataset_key)]
    return joinpath(ROOT, "data", "benchmark", "scale", "$(pct)_percentage", "$(prefix)_$(pct).txt")
end

function length_file_path(target_len::Int)::String
    dir = joinpath(ROOT, "data", "benchmark", "length", "$(target_len)_length")
    isdir(dir) || error("Không tìm thấy thư mục: $dir")
    txts = sort(filter(f -> endswith(lowercase(f), ".txt"), readdir(dir; join=true)))
    isempty(txts) && error("Không có file .txt nào trong: $dir")
    # Ưu tiên file khớp syn_T<L>_*.txt nếu có nhiều file
    preferred = filter(p -> startswith(basename(p), "syn_T$(target_len)_"), txts)
    return isempty(preferred) ? txts[1] : preferred[1]
end

# ---------------------------------------------------------------------------
# Mode 1: Sanity Check & thống kê dữ liệu
# ---------------------------------------------------------------------------

function run_stats(dataset_key::AbstractString)
    key = lowercase(dataset_key)
    haskey(SCALE_DATASETS, key) || error("Dataset '$dataset_key' không hợp lệ. Chọn: $(join(sort(collect(keys(SCALE_DATASETS))), ", "))")
    mkpath(RESULTS)
    rows = String[]

    println("=== KIỂM TRA DỮ LIỆU SCALABILITY ($key) ===")
    for pct in SCALE_LEVELS
        p = scale_file_path(key, pct)
        isfile(p) || error("Thiếu file: $p")
        st = inspect_spmf_file(p)
        line = join(["scale_$key", "$(pct)%", basename(p), st.n_trans, st.n_items, st.avg_len, st.min_len, st.max_len, st.dup_lines, st.empty_lines], ',')
        push!(rows, line)
        warn_flag = (st.dup_lines > 0 || st.empty_lines > 0) ? "  <-- KIỂM TRA LẠI" : ""
        println("  $(lpad(pct, 3))% | $(basename(p)) | |D|=$(st.n_trans) | |I|=$(st.n_items) | avg_len=$(st.avg_len) | dup=$(st.dup_lines) | empty=$(st.empty_lines)$warn_flag")
    end

    println("\n=== KIỂM TRA DỮ LIỆU ĐỘ DÀI GIAO DỊCH (length/) ===")
    for L in LENGTH_LEVELS
        p = length_file_path(L)
        st = inspect_spmf_file(p)
        line = join(["length", "T$L", basename(p), st.n_trans, st.n_items, st.avg_len, st.min_len, st.max_len, st.dup_lines, st.empty_lines], ',')
        push!(rows, line)
        warn_flag = (st.dup_lines > 0 || st.empty_lines > 0) ? "  <-- KIỂM TRA LẠI" : ""
        println("  T=$(lpad(L, 2)) | $(basename(p)) | |D|=$(st.n_trans) | |I|=$(st.n_items) | avg_len=$(st.avg_len) | dup=$(st.dup_lines) | empty=$(st.empty_lines)$warn_flag")
    end

    out_csv = joinpath(RESULTS, "dataset_stats_$(key).csv")
    write(out_csv, join([STATS_HEAD; rows], '\n') * '\n')
    println("\n-> Đã lưu bảng thống kê: $out_csv")
end

# ---------------------------------------------------------------------------
# Hàm chạy chung cho một chuỗi điểm thí nghiệm (scale hoặc length)
# ---------------------------------------------------------------------------

function run_sweep(;
    tag::AbstractString,
    items::Vector{Tuple{Int,String,String}}, # (param_value, dataset_label, filepath)
    minsups::Vector{Float64},
    engines::Vector{String},
    repeat::Int,
    timeout::Float64,
    raw_head::String,
    sum_head::String,
    raw_path::String,
    sum_path::String,
)
    mkpath(RESULTS)
    raw = String[]
    summary = String[]

    # Đọc trước thống kê cơ bản (|D|, avg_len) để ghi kèm vào CSV
    meta = Dict{String,NamedTuple}()
    for (_, _, fp) in items
        isfile(fp) || error("Thiếu file đầu vào: $fp")
        meta[fp] = inspect_spmf_file(fp)
    end

    # Với mỗi minsup (từ dễ -> khó), quét theo chiều tăng dần của tham số (10%->100% hoặc T10->T40)
    for ms in sort(minsups; rev=true)
        dead = Set{String}() # engine nào timeout/lỗi ở mức nhỏ hơn thì bỏ qua các mức lớn hơn của cùng minsup
        println("\n=== [$tag] minsup = $ms | repeat = $repeat | timeout = $(timeout)s ===")

        for (param_val, ds_label, fp) in items
            st = meta[fp]
            for eng in engines
                if eng in dead
                    push!(summary, join([ds_label, param_val, st.n_trans, st.avg_len, ms, eng, "skipped", "", "", "", "", ""], ','))
                    println("  [SKIP] $ds_label ($param_val) | ms=$ms | $eng")
                    continue
                end

                runs = RunResult[]
                for i in 1:repeat
                    r = run_once(eng, fp, ms; timeout)
                    rm(r.out; force=true) # dọn file output tạm của từng lần chạy
                    line = join([ds_label, param_val, st.n_trans, st.avg_len, ms, eng, i,
                                 r.status, fmt(r.time_ms), fmt(r.fit_ms), r.wall_s,
                                 fmt(r.peak_mb), fmt(r.n_closed)], ',')
                    push!(raw, line)
                    println("  $line")
                    if r.status != "ok"
                        push!(dead, eng)
                        runs = [r]
                        break
                    end
                    push!(runs, r)
                end

                if runs[1].status != "ok"
                    push!(summary, join([ds_label, param_val, st.n_trans, st.avg_len, ms, eng,
                                         runs[1].status, "", "", "", "", ""], ','))
                else
                    med_time = any(r -> r.time_ms === nothing, runs) ? "" : med([r.time_ms for r in runs])
                    med_fit  = (eng == "spmf" || any(r -> r.fit_ms === nothing, runs)) ? "" : med([r.fit_ms for r in runs])
                    med_wall = med([r.wall_s for r in runs])
                    med_ram  = any(r -> r.peak_mb === nothing, runs) ? "" : med([r.peak_mb for r in runs])
                    n_closed = fmt(runs[1].n_closed)
                    push!(summary, join([ds_label, param_val, st.n_trans, st.avg_len, ms, eng,
                                         "ok", med_time, med_fit, med_wall, med_ram, n_closed], ','))
                end
            end

            # Ghi tăng dần sau mỗi mức để không mất dữ liệu nếu dừng giữa chừng
            write(raw_path, join([raw_head; raw], '\n') * '\n')
            write(sum_path, join([sum_head; summary], '\n') * '\n')
        end
    end

    println("\n-> Hoàn tất [$tag]:")
    println("   Raw    : $raw_path")
    println("   Summary: $sum_path")
end

# ---------------------------------------------------------------------------
# Mode 2 & 3: Scale & Length
# ---------------------------------------------------------------------------

function bench_scale(dataset_key::AbstractString, minsups::Vector{Float64};
                     repeat::Int=3, timeout::Float64=120.0, engines::Vector{String}=collect(ENGINES))
    key = lowercase(dataset_key)
    haskey(SCALE_DATASETS, key) || error("Dataset '$dataset_key' không hợp lệ. Chọn: $(join(sort(collect(keys(SCALE_DATASETS))), ", "))")
    items = [(pct, key, scale_file_path(key, pct)) for pct in SCALE_LEVELS]
    run_sweep(
        tag      = "scale_$key",
        items    = items,
        minsups  = minsups,
        engines  = engines,
        repeat   = repeat,
        timeout  = timeout,
        raw_head = SCALE_RAW_HEAD,
        sum_head = SCALE_SUM_HEAD,
        raw_path = joinpath(RESULTS, "raw_scale_$(key).csv"),
        sum_path = joinpath(RESULTS, "summary_scale_$(key).csv"),
    )
end

function bench_length(minsups::Vector{Float64};
                      repeat::Int=3, timeout::Float64=120.0, engines::Vector{String}=collect(ENGINES))
    items = [(L, "syn_T$(L)", length_file_path(L)) for L in LENGTH_LEVELS]
    run_sweep(
        tag      = "length",
        items    = items,
        minsups  = minsups,
        engines  = engines,
        repeat   = repeat,
        timeout  = timeout,
        raw_head = LENGTH_RAW_HEAD,
        sum_head = LENGTH_SUM_HEAD,
        raw_path = joinpath(RESULTS, "raw_length.csv"),
        sum_path = joinpath(RESULTS, "summary_length.csv"),
    )
end

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

function parse_flags_and_minsups(tokens::Vector{String})
    repeat = 3
    timeout = 120.0
    engines = collect(ENGINES)
    skip_preflight = false
    minsups = Float64[]

    i = 1
    while i <= length(tokens)
        tok = tokens[i]
        if tok == "--repeat"
            repeat = parse(Int, tokens[i + 1]); i += 2
        elseif tok == "--timeout"
            timeout = parse(Float64, tokens[i + 1]); i += 2
        elseif tok == "--engines"
            engines = [strip(lowercase(e)) for e in split(tokens[i + 1], ',') if !isempty(strip(e))]
            for e in engines
                e in ENGINES || error("Engine không hợp lệ: '$e'. Chọn trong: $(join(ENGINES, ", "))")
            end
            i += 2
        elseif tok == "--skip-preflight"
            skip_preflight = true; i += 1
        else
            val = parse(Float64, tok)
            (val <= 0.0 || val > 1.0) && error("minsup tương đối phải nằm trong (0, 1], nhận: $val")
            push!(minsups, val); i += 1
        end
    end
    return (; repeat, timeout, engines, skip_preflight, minsups)
end

function run_cli(args::Vector{String})
    usage = """
    Cách dùng:
      julia scripts/bench_scale_length.jl stats <dataset>
      julia scripts/bench_scale_length.jl scale <dataset> <minsup...> [--repeat N] [--timeout S] [--engines spmf,baseline,optimized]
      julia scripts/bench_scale_length.jl length <minsup...> [--repeat N] [--timeout S] [--engines spmf,baseline,optimized]

    Dataset hỗ trợ cho stats/scale: $(join(sort(collect(keys(SCALE_DATASETS))), ", "))
    """
    if isempty(args) || args[1] in ("-h", "--help")
        println(usage)
        return 0
    end

    mode = lowercase(args[1])
    rest = args[2:end]

    if mode == "stats" && length(rest) == 1
        run_stats(rest[1])
        return 0
    elseif mode == "scale" && length(rest) >= 2
        ds = rest[1]
        cfg = parse_flags_and_minsups(rest[2:end])
        isempty(cfg.minsups) && error("Cần truyền ít nhất 1 giá trị minsup (vd: 0.005 0.001).")
        if !cfg.skip_preflight && !preflight_check(cfg.engines)
            return 1
        end
        bench_scale(ds, cfg.minsups; repeat=cfg.repeat, timeout=cfg.timeout, engines=cfg.engines)
        return 0
    elseif mode == "length" && length(rest) >= 1
        cfg = parse_flags_and_minsups(rest)
        isempty(cfg.minsups) && error("Cần truyền ít nhất 1 giá trị minsup (vd: 0.01).")
        if !cfg.skip_preflight && !preflight_check(cfg.engines)
            return 1
        end
        bench_length(cfg.minsups; repeat=cfg.repeat, timeout=cfg.timeout, engines=cfg.engines)
        return 0
    end

    println(usage)
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(run_cli(ARGS))
end
