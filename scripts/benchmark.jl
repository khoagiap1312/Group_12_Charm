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
    return `$julia --project=$ROOT $MAIN -i $inp -m $(float(minsup)) -o $out -a $engine -w 1`
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

function main(args)
    usage = "Cách dùng:\n  julia scripts/benchmark.jl compare <file> <minsup>\n  julia scripts/benchmark.jl bench <$(join(sort(collect(keys(DATASETS))), '|'))> <minsup...> [--repeat N] [--timeout giây]"
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
    end
    println(usage)
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    Sys.which("java")
    exit(main(ARGS))
end
