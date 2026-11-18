"""Chạy Baseline / Optimized (Julia) và SPMF Charm_bitset, so kết quả + đo time/peak RAM.

  python scripts/benchmark.py compare data/toy/sample.txt 0.4        # kiểm đúng sai vs SPMF
  python scripts/benchmark.py bench data/benchmark/mushroom.txt 0.3 0.2 0.1   # -> results/bench.csv
Cần: julia, java, tools/spmf.jar, psutil.
"""
import csv, os, re, subprocess, sys, tempfile, time
import psutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JAR = os.path.join(ROOT, "tests", "spmf.jar")
MAIN = os.path.join(ROOT, "src", "main.jl")

def cmd(engine, inp, out, minsup):
    if engine == "spmf":
        return ["java", "-jar", JAR, "run", "Charm_bitset", inp, out, f"{minsup * 100:g}%"]
    return ["julia", f"--project={ROOT}", MAIN, "-i", inp, "-m", str(minsup), "-o", out, "-a", engine]

def run(engine, inp, minsup):
    """Trả về (out_path, wall_s, reported_ms, peak_mb). Mỗi lần chạy = 1 tiến trình mới."""
    out = tempfile.mktemp(suffix=f"_{engine}.txt")
    t0 = time.perf_counter()
    p = subprocess.Popen(cmd(engine, inp, out, minsup), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    ps, peak = psutil.Process(p.pid), 0
    while p.poll() is None:
        try:
            peak = max(peak, ps.memory_info().rss + sum(c.memory_info().rss for c in ps.children(recursive=True)))
        except psutil.Error:
            pass
        time.sleep(0.01)
    wall = time.perf_counter() - t0
    log = p.stdout.read()
    if p.returncode:
        sys.exit(f"[{engine}] lỗi:\n{log}")
    m = re.search(r"Time: ([\d.]+) ms", log) or re.search(r"Total time ~\s*(\d+) ms", log)
    return out, wall, float(m.group(1)) if m else None, peak / 2**20

def load(path):
    res = {}
    for line in open(path):
        if line.startswith(("@", "#", "%")) or "#SUP:" not in line:
            continue
        items, sup = line.split("#SUP:")
        res[frozenset(map(int, items.split()))] = int(sup)
    return res

def compare(inp, minsup):
    ref = load(run("spmf", inp, minsup)[0])
    ok = True
    for eng in ("baseline", "optimized"):
        got = load(run(eng, inp, minsup)[0])
        miss, extra = ref.keys() - got.keys(), got.keys() - ref.keys()
        diff = {k for k in ref.keys() & got.keys() if ref[k] != got[k]}
        status = "OK" if not (miss or extra or diff) else "LỆCH"
        ok &= status == "OK"
        print(f"{eng:9s} {status}: {len(got)} vs SPMF {len(ref)} | thiếu {len(miss)}, thừa {len(extra)}, sai support {len(diff)}")
    sys.exit(0 if ok else 1)

def bench(inp, minsups, repeat=3):
    csv_path = os.path.join(ROOT, "results", "bench.csv")
    new = not os.path.exists(csv_path)
    with open(csv_path, "a", newline="") as f:
        w = csv.writer(f)
        new and w.writerow(["dataset", "minsup", "engine", "reported_ms", "wall_s", "peak_mb", "n_closed"])
        for ms in minsups:
            for eng in ("spmf", "baseline", "optimized"):
                runs = sorted((run(eng, inp, ms) for _ in range(repeat)), key=lambda r: r[1])
                out, wall, rep, peak = runs[len(runs) // 2]  # lấy trung vị theo wall time
                row = [os.path.basename(inp), ms, eng, rep, round(wall, 3), round(peak, 1), len(load(out))]
                w.writerow(row); print(row)

if __name__ == "__main__":
    mode, inp, *ms = sys.argv[1:]
    (compare if mode == "compare" else bench)(inp, float(ms[0])) if mode == "compare" else bench(inp, list(map(float, ms)))
