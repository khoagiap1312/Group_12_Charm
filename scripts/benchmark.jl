# Benchmark Baseline / Optimized CHARM (Julia) và SPMF Charm_bitset trên cùng input.
#
#   julia scripts/benchmark.jl compare data/toy/sample.txt 0.4
#       -> so từng closed itemset + support của 3 engine (kiểm đúng sai)
#   julia scripts/benchmark.jl bench chess 0.9 0.8 0.7 0.6 0.5 [--repeat 3] [--timeout 120]
#       -> chạy 3 engine, mỗi cấu hình `repeat` lần lấy trung vị, ghi results/
#
# Quy ước đo:
#   - Mỗi lần chạy là một tiến trình riêng; Julia luôn --warmup 1 để loại thời gian JIT.
#   - time_ms: thời gian nội bộ của chương trình, dùng để so với SPMF. Julia = đọc file + fit! + ghi file
#     (sau warm-up); SPMF = "Total time" do SPMF tự báo (gồm đọc DB và ghi kết quả, không gồm khởi động JVM).
#   - fit_ms: chỉ riêng thuật toán (fit!) của Julia, để phân tích Baseline vs Optimized. SPMF để trống.
#   - peak_mb: Julia = Sys.maxrss() của chính tiến trình đó (gồm ~200 MB nền của runtime);
#     SPMF = "Maximum memory usage" SPMF tự báo (heap JVM, KHÔNG cùng thước đo với RSS của Julia).
#     Vì vậy so RAM giữa Baseline và Optimized là chính.
#   - timeout: engine nào quá hạn/lỗi ở một minsup thì bỏ qua các minsup thấp hơn của engine đó.
# Cần: java, tools/spmf.jar. Chỉ dùng thư viện chuẩn của Julia.

const ROOT = dirname(@__DIR__)
const JAR = joinpath(ROOT, "tools", "spmf.jar")
const MAIN = joinpath(ROOT, "src", "main.jl")
const RESULTS = joinpath(ROOT, "results")
const ENGINES = ("spmf", "baseline", "optimized")
const DATASETS = Dict("chess" => "chess.txt", "mushroom" => "mushrooms.txt",
                      "retail" => "retail.txt", "t10i4d100k" => "T10I4D100K.txt")
const RAW_HEAD = "dataset,minsup,engine,run,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"
const SUM_HEAD = "dataset,minsup,engine,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"

function engine_cmd(engine, inp, out, minsup)
    if engine == "spmf"
        pct = string(round(minsup * 100, digits=6), "%")
        return `java -jar $JAR run Charm_bitset $inp $out $pct`
    end
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    algo, order = split_engine(engine)
    return `$julia --project=$ROOT $MAIN -i $inp -m $(float(minsup)) -o $out -a $algo -r $order -w 1`
end

# "baseline", "optimized", hoặc biến thể thứ tự item: "baseline+asc", "optimized+desc"
function split_engine(engine::AbstractString)
    parts = split(engine, '+')
    algo = String(parts[1])
    length(parts) == 1 && return algo, "none"
    parts[2] == "asc" && return algo, "support_asc"
    parts[2] == "desc" && return algo, "support_desc"
    error("Engine không hợp lệ: $engine")
end

# Kết quả một lần chạy; thiếu số liệu thì để nothing.
mutable struct RunResult
    status::String # ok | timeout | error
    time_ms::Union{Float64,Nothing}
    fit_ms::Union{Float64,Nothing}
    wall_s::Float64
    peak_mb::Union{Float64,Nothing}
    n_closed::Union{Int,Nothing}
    out::String
end

firstnum(rx, s) = (m = match(rx, s); m === nothing ? nothing : parse(Float64, m.captures[1]))

function run_once(engine, inp, minsup; timeout=Inf)
    out = tempname() * "_$engine.txt"
    t0 = time()
    proc = open(ignorestatus(pipeline(engine_cmd(engine, inp, out, minsup); stderr=stdout)), "r")
    reader = @async read(proc, String) # đọc log song song để pipe không bị đầy
    status = "ok"
    deadline = t0 + timeout
    while !process_exited(proc)
        if time() > deadline
            kill(proc)
            status = "timeout"
            break
        end
        sleep(0.005)
    end
    wait(proc)
    wall = round(time() - t0, digits=3)
    log = fetch(reader)
    r = RunResult(status, nothing, nothing, wall, nothing, nothing, out)
    if status == "ok" && proc.exitcode != 0
        r.status = "error"
        return r
    end
    status == "ok" || return r
    if engine == "spmf"
        r.time_ms = firstnum(r"Total time ~\s*(\d+) ms", log)
        r.peak_mb = firstnum(r"Maximum memory usage : ([\d.]+) mb", log)
        n = firstnum(r"closed itemsets count : (\d+)", log)
    else
        r.time_ms = firstnum(r"Total: ([\d.]+) ms", log)
        r.fit_ms = firstnum(r"Time: ([\d.]+) ms", log)
        r.peak_mb = firstnum(r"PeakRSS: ([\d.]+) MB", log)
        n = firstnum(r"Closed Itemsets: (\d+)", log)
    end
    r.n_closed = n === nothing ? nothing : Int(n)
    return r
end

# Đọc file output dạng SPMF thành Dict(Set(items) => support)
function load_result(path)
    res = Dict{Set{Int},Int}()
    for line in eachline(path)
        (startswith(line, '@') || startswith(line, '#') || startswith(line, '%') || !occursin("#SUP:", line)) && continue
        items, sup = split(line, "#SUP:")
        res[Set(parse.(Int, split(items)))] = parse(Int, strip(sup))
    end
    return res
end

function compare(inp, minsup)
    ref = load_result(run_once("spmf", inp, minsup).out)
    ok = true
    for eng in ("baseline", "optimized")
        got = load_result(run_once(eng, inp, minsup).out)
        miss = count(k -> !haskey(got, k), keys(ref))
        extra = count(k -> !haskey(ref, k), keys(got))
        wrong = count(k -> haskey(got, k) && got[k] != ref[k], keys(ref))
        good = miss == 0 && extra == 0 && wrong == 0
        ok &= good
        println(rpad(eng, 9), good ? " OK" : " LỆCH", ": $(length(got)) vs SPMF $(length(ref)) | thiếu $miss, thừa $extra, sai support $wrong")
    end
    return ok
end

fmt(x) = x === nothing ? "" : string(x)
med(v) = (s = sort(v); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)

function bench(name, minsups; repeat=3, timeout=120.0)
    inp = joinpath(ROOT, "data", "benchmark", "origin", DATASETS[name])
    isfile(inp) || error("Thiếu $inp (tải bằng scripts/load_dataset.jl)")
    mkpath(RESULTS)
    dead = Set{String}() # engine đã timeout/lỗi ở minsup cao hơn
    raw, summary = String[], String[]
    for ms in sort(minsups; rev=true), eng in ENGINES
        if eng in dead
            push!(summary, join([name, ms, eng, "skipped", "", "", "", "", ""], ','))
            continue
        end
        runs = RunResult[]
        for i in 1:repeat
            r = run_once(eng, inp, ms; timeout)
            line = join([name, ms, eng, i, r.status, fmt(r.time_ms), fmt(r.fit_ms), r.wall_s, fmt(r.peak_mb), fmt(r.n_closed)], ',')
            push!(raw, line)
            println(line)
            if r.status != "ok"
                push!(dead, eng)
                runs = [r]
                break
            end
            push!(runs, r)
        end
        if runs[1].status != "ok"
            push!(summary, join([name, ms, eng, runs[1].status, "", "", "", "", ""], ','))
        else
            push!(summary, join([name, ms, eng, "ok", med([r.time_ms for r in runs]),
                                 eng == "spmf" ? "" : med([r.fit_ms for r in runs]), med([r.wall_s for r in runs]),
                                 med([r.peak_mb for r in runs]), runs[1].n_closed], ','))
        end
    end
    write(joinpath(RESULTS, "raw_$name.csv"), join([RAW_HEAD; raw], '\n') * '\n')
    write(joinpath(RESULTS, "summary_$name.csv"), join([SUM_HEAD; summary], '\n') * '\n')
    println("-> results/summary_$name.csv")
end

# ---------- Correctness: so từng itemset của các engine với SPMF ----------
function compare_engines(inp, minsup, engines)
    r = run_once("spmf", inp, minsup)
    r.status == "ok" || error("SPMF lỗi trên $inp (minsup=$minsup): $(r.status)")
    ref = load_result(r.out)
    rows = NamedTuple[]
    for eng in engines
        g = run_once(eng, inp, minsup)
        g.status == "ok" || error("$eng lỗi trên $inp (minsup=$minsup): $(g.status)")
        got = load_result(g.out)
        matched = count(k -> haskey(got, k) && got[k] == ref[k], keys(ref))
        miss = count(k -> !haskey(got, k), keys(ref))
        extra = count(k -> !haskey(ref, k), keys(got))
        wrong = count(k -> haskey(got, k) && got[k] != ref[k], keys(ref))
        union_n = length(ref) + extra
        rate = union_n == 0 ? 100.0 : 100.0 * matched / union_n # khớp hoàn toàn / hợp hai tập, giống verify_correctness.jl
        push!(rows, (engine=eng, spmf=length(ref), ours=length(got), matched=matched, miss=miss, extra=extra, wrong=wrong, rate=rate))
    end
    return rows
end

const CORRECT_PLAN = [("chess", [0.9, 0.8, 0.7, 0.6]), ("mushroom", [0.5, 0.3, 0.1]),
                      ("retail", [0.01, 0.005, 0.002]), ("t10i4d100k", [0.01, 0.005, 0.0025])]

function correctness()
    mkpath(RESULTS)
    lines = ["dataset,minsup,engine,spmf_count,ours_count,matched,missing,extra,wrong_support,match_rate"]
    println(lines[1])
    for (name, mss) in CORRECT_PLAN, ms in mss
        inp = joinpath(ROOT, "data", "benchmark", "origin", DATASETS[name])
        isfile(inp) || error("Thiếu $inp (tải bằng scripts/load_dataset.jl)")
        for r in compare_engines(inp, ms, ("baseline", "optimized", "baseline+asc", "optimized+asc"))
            push!(lines, join([name, ms, r.engine, r.spmf, r.ours, r.matched, r.miss, r.extra, r.wrong, round(r.rate, digits=2)], ','))
            println(lines[end]); flush(stdout)
        end
    end
    write(joinpath(RESULTS, "correctness.csv"), join(lines, '\n') * '\n')
    println("-> results/correctness.csv")
end

# ---------- Sweep tổng quát: scalability, độ dài giao dịch, so sánh thứ tự item ----------
const SWEEP_RAW_HEAD = "experiment,group,x,minsup,engine,run,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"
const SWEEP_SUM_HEAD = "experiment,group,x,minsup,engine,status,time_ms,fit_ms,wall_s,peak_mb,n_closed"

# jobs: danh sách (group, x, đường dẫn, minsup). Engine quá hạn/lỗi ở một job thì bỏ qua các job sau của cùng group.
function run_sweep(tag, jobs, engines; repeat=3, timeout=120.0)
    mkpath(RESULTS)
    for (_, _, inp, _) in jobs
        isfile(inp) || error("Thiếu $inp (tải bằng scripts/load_dataset.jl)")
    end
    dead = Set{Tuple{String,String}}()
    raw, summary = String[], String[]
    for (group, x, inp, ms) in jobs, eng in engines
        key = (eng, group)
        if key in dead
            push!(summary, join([tag, group, x, ms, eng, "skipped", "", "", "", "", ""], ','))
            continue
        end
        runs = RunResult[]
        for i in 1:repeat
            r = run_once(eng, inp, ms; timeout)
            line = join([tag, group, x, ms, eng, i, r.status, fmt(r.time_ms), fmt(r.fit_ms), r.wall_s, fmt(r.peak_mb), fmt(r.n_closed)], ',')
            push!(raw, line)
            println(line); flush(stdout)
            if r.status != "ok"
                push!(dead, key)
                runs = [r]
                break
            end
            push!(runs, r)
        end
        if runs[1].status != "ok"
            push!(summary, join([tag, group, x, ms, eng, runs[1].status, "", "", "", "", ""], ','))
        else
            push!(summary, join([tag, group, x, ms, eng, "ok", med([r.time_ms for r in runs]),
                                 eng == "spmf" ? "" : med([r.fit_ms for r in runs]), med([r.wall_s for r in runs]),
                                 med([r.peak_mb for r in runs]), runs[1].n_closed], ','))
        end
    end
    write(joinpath(RESULTS, "raw_$tag.csv"), join([SWEEP_RAW_HEAD; raw], '\n') * '\n')
    write(joinpath(RESULTS, "summary_$tag.csv"), join([SWEEP_SUM_HEAD; summary], '\n') * '\n')
    println("-> results/summary_$tag.csv")
end

bench_dir(sub...) = joinpath(ROOT, "data", "benchmark", sub...)

# Scalability: tập con 10/25/50/75/100% giao dịch, minsup tương đối cố định
function scale_jobs(name, minsups)
    stem = splitext(DATASETS[name])[1]
    [("minsup=$ms", string(pct), bench_dir("scale", "$(pct)_percentage", "$(stem)_$(pct).txt"), ms)
     for ms in minsups for pct in (10, 25, 50, 75, 100)]
end

# Ảnh hưởng độ dài giao dịch: CSDL tổng hợp T10..T40 (20.000 giao dịch, cùng số item)
length_jobs(minsups) = [("minsup=$ms", string(t), bench_dir("length", "$(t)_length", "syn_T$(t)_I4_D20000.txt"), ms)
                        for ms in minsups for t in 10:5:40]

# So sánh thứ tự item: mặc định / support tăng dần / support giảm dần, cho cả hai bản
const IMPROVE_PLAN = [("chess", [0.7, 0.6]), ("mushroom", [0.2, 0.1]),
                      ("retail", [0.005, 0.001]), ("t10i4d100k", [0.005, 0.001])]
improve_jobs() = [("$name@$ms", "", bench_dir("origin", DATASETS[name]), ms) for (name, mss) in IMPROVE_PLAN for ms in mss]
const IMPROVE_ENGINES = ("baseline", "baseline+asc", "baseline+desc", "optimized", "optimized+asc", "optimized+desc")

# Tách tham số vị trí và các tuỳ chọn --repeat/--timeout
function parse_sweep_args(rest)
    repeat, timeout, pos = 3, 120.0, String[]
    i = 1
    while i <= length(rest)
        if rest[i] == "--repeat"
            repeat = parse(Int, rest[i+1]); i += 2
        elseif rest[i] == "--timeout"
            timeout = parse(Float64, rest[i+1]); i += 2
        else
            push!(pos, rest[i]); i += 1
        end
    end
    return pos, repeat, timeout
end

function main(args)
    usage = """
    Cách dùng:
      julia scripts/benchmark.jl compare <file> <minsup>
      julia scripts/benchmark.jl bench <$(join(sort(collect(keys(DATASETS))), '|'))> <minsup...> [--repeat N] [--timeout giây]
      julia scripts/benchmark.jl scale <dataset> <minsup...> [--repeat N] [--timeout giây]   # tập con 10-100% giao dịch
      julia scripts/benchmark.jl length <minsup...> [--repeat N] [--timeout giây]            # CSDL tổng hợp T10-T40
      julia scripts/benchmark.jl improve [--repeat N] [--timeout giây]                       # so sánh thứ tự item
      julia scripts/benchmark.jl correctness                                                 # bảng khớp SPMF trên 4 tập"""
    isempty(args) && (println(usage); return 1)
    mode, rest = args[1], args[2:end]
    if mode == "compare" && length(rest) == 2
        return compare(rest[1], parse(Float64, rest[2])) ? 0 : 1
    elseif mode == "bench" && length(rest) >= 2 && haskey(DATASETS, rest[1])
        repeat, timeout, minsups = 3, 120.0, Float64[]
        i = 2
        while i <= length(rest)
            if rest[i] == "--repeat"
                repeat = parse(Int, rest[i+1]); i += 2
            elseif rest[i] == "--timeout"
                timeout = parse(Float64, rest[i+1]); i += 2
            else
                push!(minsups, parse(Float64, rest[i])); i += 1
            end
        end
        bench(rest[1], minsups; repeat, timeout)
        return 0
    elseif mode == "scale"
        pos, repeat, timeout = parse_sweep_args(rest)
        (length(pos) >= 2 && haskey(DATASETS, pos[1])) || (println(usage); return 1)
        run_sweep("scale_$(pos[1])", scale_jobs(pos[1], parse.(Float64, pos[2:end])), ENGINES; repeat, timeout)
        return 0
    elseif mode == "length"
        pos, repeat, timeout = parse_sweep_args(rest)
        isempty(pos) && (println(usage); return 1)
        run_sweep("length", length_jobs(parse.(Float64, pos)), ENGINES; repeat, timeout)
        return 0
    elseif mode == "improve"
        _, repeat, timeout = parse_sweep_args(rest)
        run_sweep("improve", improve_jobs(), IMPROVE_ENGINES; repeat, timeout)
        return 0
    elseif mode == "correctness"
        correctness()
        return 0
    end
    println(usage)
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
