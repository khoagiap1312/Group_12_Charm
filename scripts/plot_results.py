"""Vẽ 6 nhóm biểu đồ của Chương 2 và sinh các bảng số liệu từ results/*.csv.

    python scripts/plot_results.py

Đầu ra:
    docs/figures/*.png và *.pdf   các biểu đồ (PDF dùng cho báo cáo IEEE)
    docs/tables_tv2.md            các bảng số liệu (để dán vào báo cáo, luôn khớp với results/)
Chỉ cần matplotlib. Hình nào thiếu dữ liệu đầu vào thì bỏ qua và báo.
"""
import csv
import os
import statistics
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "results")
FIG = os.path.join(ROOT, "docs", "figures")
ORIGIN = os.path.join(ROOT, "data", "benchmark", "origin")

DATASETS = [  # (khóa, tên hiển thị, loại, file gốc)
    ("chess", "Chess", "dày", "chess.txt"),
    ("mushroom", "Mushroom", "dày", "mushrooms.txt"),
    ("retail", "Retail", "thưa", "retail.txt"),
    ("t10i4d100k", "T10I4D100K", "thưa", "T10I4D100K.txt"),
]
COLOR = {"spmf": "#6b6b6b", "baseline": "#1f77b4", "optimized": "#d95f02"}
LABEL = {"spmf": "SPMF Charm_bitset", "baseline": "Baseline (mảng)", "optimized": "Optimized (bitset)"}
MARK = {"spmf": "s", "baseline": "o", "optimized": "^"}

plt.rcParams.update({"font.size": 9, "axes.grid": True, "grid.alpha": 0.3, "axes.axisbelow": True,
                     "figure.dpi": 110, "savefig.dpi": 200, "axes.spines.top": False, "axes.spines.right": False})


def read(name):
    path = os.path.join(RES, name)
    if not os.path.exists(path):
        print(f"  [bỏ qua] thiếu {name}")
        return None
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(x):
    return float(x) if x not in ("", None) else None


def save(fig, name):
    os.makedirs(FIG, exist_ok=True)
    for ext in ("png", "pdf"):
        fig.savefig(os.path.join(FIG, f"{name}.{ext}"), bbox_inches="tight")
    plt.close(fig)
    print(f"  -> docs/figures/{name}.png|pdf")


def summary(key):
    """{(minsup, engine): row} chỉ gồm các dòng ok."""
    rows = read(f"summary_{key}.csv")
    if rows is None:
        return None
    return {(float(r["minsup"]), r["engine"]): r for r in rows if r["status"] == "ok"}


def minsups(s):
    return sorted({k[0] for k in s}, reverse=True)


def series(s, engine, field):
    xs = [m for m in minsups(s) if (m, engine) in s and s[(m, engine)][field] != ""]
    return xs, [float(s[(m, engine)][field]) for m in xs]


def style_x(ax, kind, xs):
    ax.set_xscale("log" if kind == "thưa" else "linear")
    ax.invert_xaxis()  # minsup giảm dần từ trái sang phải
    ax.set_xlabel("minsup (tỉ lệ giao dịch, giảm dần)")


# ---------------------------------------------------------------- 1. Correctness
def fig_correctness():
    rows = read("correctness.csv")
    if rows is None:
        return
    engines = ["baseline", "optimized", "baseline+asc", "optimized+asc"]
    names = {"baseline": "Baseline", "optimized": "Optimized", "baseline+asc": "Baseline + support tăng",
             "optimized+asc": "Optimized + support tăng"}
    cols = {"baseline": "#1f77b4", "optimized": "#d95f02", "baseline+asc": "#9ecae1", "optimized+asc": "#fdae6b"}
    fig, axes = plt.subplots(1, 4, figsize=(11, 3.2), sharey=True)
    for ax, (key, disp, kind, _) in zip(axes, DATASETS):
        sub = [r for r in rows if r["dataset"] == key]
        ms = sorted({float(r["minsup"]) for r in sub}, reverse=True)
        w = 0.8 / len(engines)
        for i, e in enumerate(engines):
            vals = [next(float(r["match_rate"]) for r in sub if float(r["minsup"]) == m and r["engine"] == e) for m in ms]
            ax.bar([j + i * w for j in range(len(ms))], vals, w, color=cols[e], label=names[e])
        ax.set_xticks([j + 0.4 - w / 2 for j in range(len(ms))])
        ax.set_xticklabels([f"{m:g}" for m in ms])
        ax.set_title(f"{disp} ({kind})")
        ax.set_xlabel("minsup")
        ax.set_ylim(0, 112)
        ax.axhline(100, color="k", lw=0.6, ls="--")
    axes[0].set_ylabel("Tỉ lệ itemset khớp SPMF (%)")
    axes[0].legend(loc="lower left", fontsize=7, framealpha=0.9)
    fig.tight_layout()
    save(fig, "fig1_correctness")


# ---------------------------------------------------------------- 2. Thời gian theo minsup
def fig_time():
    fig, axes = plt.subplots(2, 2, figsize=(8.5, 6))
    for ax, (key, disp, kind, _) in zip(axes.flat, DATASETS):
        s = summary(key)
        if s is None:
            continue
        for e in ("spmf", "baseline", "optimized"):
            xs, ys = series(s, e, "time_ms")
            ax.plot(xs, ys, marker=MARK[e], color=COLOR[e], label=LABEL[e], lw=1.4, ms=4)
        ax.set_yscale("log")
        style_x(ax, kind, None)
        ax.set_ylabel("Thời gian tổng (ms, thang log)")
        ax.set_title(f"{disp} ({kind})")
    axes[0, 0].legend(fontsize=7)
    fig.tight_layout()
    save(fig, "fig2_time_vs_minsup")


def fig_speedup():
    fig, axes = plt.subplots(2, 2, figsize=(8.5, 6))
    for ax, (key, disp, kind, _) in zip(axes.flat, DATASETS):
        s = summary(key)
        if s is None:
            continue
        for e in ("baseline", "optimized"):
            xs, ys = series(s, e, "fit_ms")
            ax.plot(xs, ys, marker=MARK[e], color=COLOR[e], label=LABEL[e], lw=1.4, ms=4)
        xb, yb = series(s, "baseline", "fit_ms")
        xo, yo = series(s, "optimized", "fit_ms")
        sp = [b / o for b, o in zip(yb, yo)]
        ax.set_yscale("log")
        style_x(ax, kind, None)
        ax.set_ylabel("Thời gian thuật toán fit! (ms, thang log)")
        ax.set_title(f"{disp} ({kind}): tăng tốc {min(sp):.1f}x đến {max(sp):.1f}x")
    axes[0, 0].legend(fontsize=7)
    fig.tight_layout()
    save(fig, "fig2b_baseline_vs_optimized")


# ---------------------------------------------------------------- 3. Số itemset
def fig_itemsets():
    fig, axes = plt.subplots(1, 2, figsize=(8.5, 3.4))
    cols = {"chess": "#1b9e77", "mushroom": "#7570b3", "retail": "#d95f02", "t10i4d100k": "#e7298a"}
    for ax, kind in zip(axes, ("dày", "thưa")):
        for key, disp, k, _ in DATASETS:
            if k != kind:
                continue
            s = summary(key)
            if s is None:
                continue
            xs, ys = series(s, "optimized", "n_closed")
            ax.plot(xs, ys, marker="o", color=cols[key], label=disp, lw=1.4, ms=4)
        ax.set_yscale("log")
        style_x(ax, kind, None)
        ax.set_ylabel("Số tập đóng phổ biến (thang log)")
        ax.set_title(f"Dữ liệu {kind}")
        ax.legend(fontsize=8)
    fig.tight_layout()
    save(fig, "fig3_closed_itemsets")


# ---------------------------------------------------------------- 4. Peak RAM
def mid_minsup(s):
    ms = minsups(s)
    return ms[len(ms) // 2]


def fig_ram():
    fig, axes = plt.subplots(1, 2, figsize=(9, 3.6))
    ax = axes[0]
    names, base, opt, floor = [], [], [], []
    for key, disp, kind, _ in DATASETS:
        s = summary(key)
        if s is None:
            continue
        m = mid_minsup(s)
        names.append(f"{disp}\nminsup={m:g}")
        base.append(float(s[(m, "baseline")]["peak_mb"]))
        opt.append(float(s[(m, "optimized")]["peak_mb"]))
        floor += [float(r["peak_mb"]) for k, r in s.items() if k[1] in ("baseline", "optimized")]
    w = 0.38
    xs = range(len(names))
    b1 = ax.bar([x - w / 2 for x in xs], base, w, color=COLOR["baseline"], label=LABEL["baseline"])
    b2 = ax.bar([x + w / 2 for x in xs], opt, w, color=COLOR["optimized"], label=LABEL["optimized"])
    for b in list(b1) + list(b2):
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 3, f"{b.get_height():.0f}", ha="center", fontsize=7)
    ax.axhline(min(floor), color="k", ls="--", lw=0.8)
    ax.text(len(names) - 0.5, min(floor) - 22, f"RSS nền của runtime Julia ≈ {min(floor):.0f} MB", ha="right", fontsize=7)
    ax.set_xticks(list(xs))
    ax.set_xticklabels(names, fontsize=8)
    ax.set_ylabel("Peak RAM của tiến trình (MB)")
    ax.set_title("Peak RAM tại minsup trung bình")
    ax.legend(fontsize=7, loc="upper left")
    ax = axes[1]
    for key, disp, kind, _ in DATASETS:
        s = summary(key)
        if s is None:
            continue
        xb, yb = series(s, "baseline", "peak_mb")
        xo, yo = series(s, "optimized", "peak_mb")
        # vẽ theo thứ hạng minsup (1 = cao nhất) để 4 tập dữ liệu có cùng trục
        ax.plot(range(1, len(xb) + 1), [o - b for b, o in zip(yb, yo)], marker="o", lw=1.4, ms=4, label=f"{disp} ({kind})")
    ax.axhline(0, color="k", lw=0.8)
    ax.set_xlabel("Mức minsup (1 = cao nhất, giảm dần)")
    ax.set_ylabel("RAM Optimized − RAM Baseline (MB)")
    ax.set_title("Chênh lệch RAM theo mức minsup")
    ax.legend(fontsize=7)
    fig.tight_layout()
    save(fig, "fig4_peak_ram")


# ---------------------------------------------------------------- 5. Scalability
def fig_scalability():
    s_rows = read("summary_tv2_scale_retail.csv")
    if s_rows is None:
        return
    groups = sorted({r["group"] for r in s_rows}, reverse=True)
    fig, axes = plt.subplots(1, len(groups), figsize=(4.2 * len(groups), 3.5), squeeze=False)
    for ax, g in zip(axes[0], groups):
        sub = [r for r in s_rows if r["group"] == g and r["status"] == "ok"]
        for e in ("spmf", "baseline", "optimized"):
            pts = sorted((float(r["x"]), float(r["time_ms"])) for r in sub if r["engine"] == e)
            if pts:
                ax.plot([p[0] for p in pts], [p[1] for p in pts], marker=MARK[e], color=COLOR[e], label=LABEL[e], lw=1.4, ms=4)
        opt = sorted((float(r["x"]), float(r["time_ms"])) for r in sub if r["engine"] == "optimized")
        if opt:
            x0, y0 = opt[0]
            ax.plot([p[0] for p in opt], [y0 * p[0] / x0 for p in opt], color="k", ls=":", lw=1, label="Tuyến tính (tham chiếu)")
        ax.set_xlabel("Kích thước CSDL (% số giao dịch của Retail)")
        ax.set_ylabel("Thời gian tổng (ms)")
        ax.set_title(f"Retail, {g.replace('minsup=', 'minsup = ')}")
    axes[0][0].legend(fontsize=7)
    fig.tight_layout()
    save(fig, "fig5_scalability")


# ---------------------------------------------------------------- 6. Độ dài giao dịch
def fig_length():
    s_rows = read("summary_tv2_length.csv")
    if s_rows is None:
        return
    groups = sorted({r["group"] for r in s_rows}, reverse=True)
    fig, axes = plt.subplots(1, len(groups), figsize=(4.2 * len(groups), 3.5), squeeze=False)
    for ax, g in zip(axes[0], groups):
        sub = [r for r in s_rows if r["group"] == g and r["status"] == "ok"]
        for e in ("spmf", "baseline", "optimized"):
            pts = sorted((float(r["x"]), float(r["time_ms"])) for r in sub if r["engine"] == e)
            if pts:
                ax.plot([p[0] for p in pts], [p[1] for p in pts], marker=MARK[e], color=COLOR[e], label=LABEL[e], lw=1.4, ms=4)
        ax.set_yscale("log")
        ax.set_xlabel("Độ dài giao dịch trung bình T (số item)")
        ax.set_ylabel("Thời gian tổng (ms, thang log)")
        ax.set_title(f"CSDL tổng hợp, {g.replace('minsup=', 'minsup = ')}")
    axes[0][0].legend(fontsize=7)
    fig.tight_layout()
    save(fig, "fig6_transaction_length")


# ---------------------------------------------------------------- 7. Hướng cải tiến: thứ tự item
def fig_item_order():
    rows = read("summary_improve.csv")
    if rows is None:
        return
    ok = {(r["group"], r["engine"]): float(r["fit_ms"]) for r in rows if r["status"] == "ok" and r["fit_ms"] != ""}
    groups = []
    for r in rows:
        if r["group"] not in groups:
            groups.append(r["group"])
    series_def = [("baseline+asc", "baseline", "Baseline, support tăng", "#9ecae1"),
                  ("baseline+desc", "baseline", "Baseline, support giảm", "#08519c"),
                  ("optimized+asc", "optimized", "Optimized, support tăng", "#fdae6b"),
                  ("optimized+desc", "optimized", "Optimized, support giảm", "#a63603")]
    fig, ax = plt.subplots(figsize=(9, 3.6))
    w = 0.2
    for i, (eng, ref, lab, col) in enumerate(series_def):
        vals = [ok[(g, ref)] / ok[(g, eng)] if (g, eng) in ok and (g, ref) in ok else float("nan") for g in groups]
        ax.bar([j + (i - 1.5) * w for j in range(len(groups))], vals, w, color=col, label=lab)
    ax.axhline(1, color="k", lw=0.8)
    ax.set_yscale("log")
    ax.set_xticks(range(len(groups)))
    ax.set_xticklabels([g.replace("@", "\nminsup=") for g in groups], fontsize=7)
    ax.set_ylabel("Tăng tốc so với thứ tự mặc định (lần, log)")
    ax.set_title("Ảnh hưởng của thứ tự duyệt item (> 1: nhanh hơn mặc định)")
    ax.legend(fontsize=7, ncol=2)
    fig.tight_layout()
    save(fig, "fig7_item_order")


# ---------------------------------------------------------------- 8. Giải thích bằng số liệu: mật độ tidset và Diffset
def fig_analysis():
    d = read("analysis_density.csv")
    f = read("analysis_diffset.csv")
    if d is None or f is None:
        return
    fig, axes = plt.subplots(1, 2, figsize=(9.5, 3.6))
    labels = [f"{r['dataset']}\n{float(r['minsup']):g}" for r in d]
    ax = axes[0]
    w = 0.38
    ax.bar([i - w / 2 for i in range(len(d))], [100 * float(r["share_lt_words"]) for r in d], w, color="#9ecae1", label="|a|+|b| < n/64")
    ax.bar([i + w / 2 for i in range(len(d))], [100 * float(r["share_lt_8words"]) for r in d], w, color="#3182bd", label="|a|+|b| < 8·n/64")
    ax.set_xticks(range(len(d)))
    ax.set_xticklabels(labels, fontsize=7)
    ax.set_ylabel("Tỉ lệ phép giao (%)")
    ax.set_title("Phép giao có tidset ngắn hơn bề rộng bitset")
    ax.legend(fontsize=7)
    ax = axes[1]
    labels = [f"{r['dataset']}\n{float(r['minsup']):g}" for r in f]
    ax.bar([i - w / 2 for i in range(len(f))], [float(r["mean_tidset"]) for r in f], w, color="#1f77b4", label="Tidset |t(XY)|")
    ax.bar([i + w / 2 for i in range(len(f))], [float(r["mean_diffset"]) for r in f], w, color="#d95f02", label="Diffset |d(XY)|")
    ax.set_yscale("log")
    ax.set_xticks(range(len(f)))
    ax.set_xticklabels(labels, fontsize=7)
    ax.set_ylabel("Kích thước trung bình (số phần tử, log)")
    ax.set_title("Tidset và Diffset của các cặp item phổ biến")
    ax.legend(fontsize=7)
    fig.tight_layout()
    save(fig, "fig8_density_and_diffset")


# ---------------------------------------------------------------- Bảng số liệu (markdown)
def dataset_stats(fname):
    path = os.path.join(ORIGIN, fname)
    if not os.path.exists(path):
        return None
    n = total = 0
    items = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            toks = line.split()
            if toks:
                n += 1
                total += len(toks)
                items.update(toks)
    return n, len(items), total / n, 100 * total / n / len(items)


def md_table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out) + "\n"


def write_tables():
    parts = []
    # B1: thống kê dữ liệu
    rows = []
    for key, disp, kind, fname in DATASETS:
        st = dataset_stats(fname)
        if st:
            rows.append([disp, kind, f"{st[0]:,}", f"{st[1]:,}", f"{st[2]:.1f}", f"{st[3]:.1f}%"])
    if rows:
        parts.append("### B1. Thống kê các tập benchmark\n\n" + md_table(
            ["Tập dữ liệu", "Loại", "Số giao dịch", "Số item", "Độ dài TB", "Độ dày"], rows))
    # B2: trước/sau
    rows = []
    for key, disp, kind, _ in DATASETS:
        s = summary(key)
        if s is None:
            continue
        for m in minsups(s):
            if (m, "baseline") in s and (m, "optimized") in s:
                b, o = s[(m, "baseline")], s[(m, "optimized")]
                rows.append([disp, f"{m:g}", f"{int(float(b['n_closed'])):,}", f"{float(b['fit_ms']):.1f}", f"{float(o['fit_ms']):.1f}",
                             f"{float(b['fit_ms']) / float(o['fit_ms']):.1f}x", f"{float(b['peak_mb']):.0f}", f"{float(o['peak_mb']):.0f}"])
    if rows:
        parts.append("### B2. Baseline và Optimized: thời gian thuật toán (ms, trung vị 3 lần) và peak RAM (MB)\n\n" + md_table(
            ["Dataset", "minsup", "Số tập đóng", "Baseline (ms)", "Optimized (ms)", "Tăng tốc", "RAM Base", "RAM Opt"], rows))
    # B3: so với SPMF
    rows = []
    for key, disp, kind, _ in DATASETS:
        s = summary(key)
        if s is None:
            continue
        for m in minsups(s):
            if all((m, e) in s for e in ("spmf", "baseline", "optimized")):
                t = {e: float(s[(m, e)]["time_ms"]) for e in ("spmf", "baseline", "optimized")}
                rows.append([disp, f"{m:g}", f"{t['spmf']:.0f}", f"{t['baseline']:.0f}", f"{t['optimized']:.0f}", f"{t['spmf'] / t['optimized']:.2f}x"])
    if rows:
        parts.append("### B3. Thời gian tổng (ms) của SPMF, Baseline, Optimized. Cột cuối: SPMF / Optimized (> 1: Optimized nhanh hơn)\n\n" + md_table(
            ["Dataset", "minsup", "SPMF", "Baseline", "Optimized", "SPMF/Opt"], rows))
    # B4: correctness
    c = read("correctness.csv")
    if c:
        rows = []
        for key, disp, kind, _ in DATASETS:
            sub = [r for r in c if r["dataset"] == key]
            for m in sorted({float(r["minsup"]) for r in sub}, reverse=True):
                line = {r["engine"]: r for r in sub if float(r["minsup"]) == m}
                rows.append([disp, f"{m:g}", line["baseline"]["spmf_count"]] + [
                    f"{line[e]['matched']}/{line[e]['spmf_count']} ({float(line[e]['match_rate']):.2f}%)" for e in ("baseline", "optimized", "baseline+asc", "optimized+asc")])
        parts.append("### B4. Correctness: số itemset khớp hoàn toàn (cả itemset và support) với SPMF\n\n" + md_table(
            ["Dataset", "minsup", "Số itemset SPMF", "Baseline", "Optimized", "Baseline+asc", "Optimized+asc"], rows))
    # B5: scalability và length
    for tag, title, xname in (("tv2_scale_retail", "B5. Scalability trên Retail: thời gian tổng (ms)", "% giao dịch"),
                              ("tv2_length", "B6. Ảnh hưởng độ dài giao dịch: thời gian tổng (ms)", "T")):
        r = read(f"summary_{tag}.csv")
        if r:
            rows = []
            for g in sorted({x["group"] for x in r}, reverse=True):
                for xv in sorted({float(x["x"]) for x in r if x["group"] == g}):
                    cell = {x["engine"]: x for x in r if x["group"] == g and float(x["x"]) == xv}
                    rows.append([g, f"{xv:g}"] + [f"{float(cell[e]['time_ms']):.0f}" if e in cell and cell[e]["status"] == "ok" else (cell[e]["status"] if e in cell else "-")
                                                  for e in ("spmf", "baseline", "optimized")] + [cell["optimized"]["n_closed"] if "optimized" in cell else "-"])
            parts.append(f"### {title}\n\n" + md_table(["Nhóm", xname, "SPMF", "Baseline", "Optimized", "Số tập đóng"], rows))
    # B7: thứ tự item
    r = read("summary_improve.csv")
    if r:
        ok = {(x["group"], x["engine"]): float(x["fit_ms"]) for x in r if x["status"] == "ok" and x["fit_ms"] != ""}
        groups = []
        for x in r:
            if x["group"] not in groups:
                groups.append(x["group"])
        rows = []
        for g in groups:
            row = [g.replace("@", ", minsup=")]
            for ref in ("baseline", "optimized"):
                for suf in ("", "+asc", "+desc"):
                    row.append(f"{ok[(g, ref + suf)]:.0f}" if (g, ref + suf) in ok else "-")
            rows.append(row)
        parts.append("### B7. Thứ tự duyệt item: thời gian thuật toán fit! (ms)\n\n" + md_table(
            ["Cấu hình", "Base mặc định", "Base tăng", "Base giảm", "Opt mặc định", "Opt tăng", "Opt giảm"], rows))
    # B8: phân tích mật độ và diffset
    d = read("analysis_density.csv")
    f = read("analysis_diffset.csv")
    if d:
        parts.append("### B8. Kích thước tidset trong các phép giao (n/64 = số từ của một bitset)\n\n" + md_table(
            ["Dataset", "minsup", "n", "n/64", "Số phép giao", "|a|+|b| trung bình", "tỉ số với n/64", "% phép giao < n/64", "% phép giao < 8·n/64"],
            [[r["dataset"], f"{float(r['minsup']):g}", r["n_tx"], r["words"], f"{int(r['intersections']):,}", r["mean_ab"], r["ratio"],
              f"{100 * float(r['share_lt_words']):.1f}%", f"{100 * float(r['share_lt_8words']):.1f}%"] for r in d]))
    if f:
        parts.append("### B9. Tidset và Diffset của các cặp item phổ biến\n\n" + md_table(
            ["Dataset", "minsup", "Số item phổ biến", "% item có Diffset nhỏ hơn", "Số cặp", "|t(XY)| TB", "|d(XY)| TB", "% cặp có Diffset nhỏ hơn"],
            [[r["dataset"], f"{float(r['minsup']):g}", r["frequent_items"], f"{100 * float(r['item_diffset_smaller']):.1f}%", f"{int(r['pairs']):,}",
              r["mean_tidset"], r["mean_diffset"], f"{100 * float(r['pair_diffset_smaller']):.1f}%"] for r in f]))
    path = os.path.join(ROOT, "docs", "tables_tv2.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("<!-- Sinh tự động bởi scripts/plot_results.py từ results/*.csv, không sửa tay -->\n\n" + "\n".join(parts))
    print("  -> docs/tables_tv2.md")


def main():
    print("Vẽ biểu đồ:")
    for fn in (fig_correctness, fig_time, fig_speedup, fig_itemsets, fig_ram, fig_scalability, fig_length, fig_item_order, fig_analysis):
        fn()
    print("Sinh bảng số liệu:")
    write_tables()


if __name__ == "__main__":
    sys.exit(main())
