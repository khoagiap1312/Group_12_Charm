"""
Ứng dụng 2: Phân tích Closed Frequent Itemsets của Visual Words trên Caltech-101
- Tách transactions.txt theo từng lớp (airplanes, motorbikes, faces_easy) để chạy CHARM của nhóm.
- Đọc kết quả CHARM (toàn bộ và theo từng lớp) ở nhiều mức minsup.
- Tính độ tinh khiết theo lớp (class purity) cho từng Closed Itemset (len >= 2).
- Hiển thị trực quan lưới patch (patches/word_XXX.png) của các visual word trong itemset phổ biến nhất.
- Xuất bảng CSV và biểu đồ phục vụ báo cáo.

Cách chạy (từ thư mục gốc Group_12_Charm):
  1) Tách file giao dịch theo từng lớp trước khi chạy CHARM theo lớp:
       python scripts/analyze_caltech101.py --split-classes
  2) Phân tích & vẽ lưới patch sau khi đã chạy CHARM:
       python scripts/analyze_caltech101.py
"""

import argparse
import re
from pathlib import Path

import matplotlib.image as mpimg
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# ==============================================================================
# CẤU HÌNH ĐƯỜNG DẪN (khớp với cấu trúc dự án Group_12_Charm)
# ==============================================================================
PRE_DIR = Path("data/application/cal_tech_101/pre_process")
TX_ALL_PATH = PRE_DIR / "transactions.txt"
IMG_MAP_PATH = PRE_DIR / "image_mapping.csv"
WORD_STATS_PATH = PRE_DIR / "visual_word_stats.csv"
PATCH_DIR = PRE_DIR / "patches"

OUT_DIR = Path("results/application/cal_tech_101")
FIG_DIR = OUT_DIR / "figures"

TARGET_CLASSES = ["airplanes", "motorbikes", "faces_easy"]


def load_transactions(tx_path: Path) -> list[frozenset[int]]:
    txs: list[frozenset[int]] = []
    with open(tx_path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s:
                txs.append(frozenset(int(x) for x in s.split()))
    return txs


def split_transactions_by_class() -> None:
    df_img = pd.read_csv(IMG_MAP_PATH)
    with open(TX_ALL_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(df_img), (
        f"Số dòng transactions.txt ({len(lines)}) != image_mapping.csv ({len(df_img)})"
    )

    for cls in TARGET_CLASSES:
        cls_indices = df_img.index[df_img["class_name"] == cls].tolist()
        out_path = PRE_DIR / f"transactions_{cls}.txt"
        with open(out_path, "w", encoding="utf-8") as fout:
            for idx in cls_indices:
                fout.write(lines[idx] + "\n")
        print(f"[DONE] Đã xuất {len(cls_indices)} giao dịch lớp '{cls}' -> {out_path}")


def parse_charm_output(path: Path) -> list[tuple[frozenset[int], int]]:
    itemsets: list[tuple[frozenset[int], int]] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or "#SUP:" not in line:
                continue
            items_part, sup_part = line.split("#SUP:", 1)
            ids = frozenset(int(x) for x in items_part.strip().split())
            sup = int(sup_part.strip())
            if ids:
                itemsets.append((ids, sup))
    return itemsets


def extract_minsup(filename: str) -> float | None:
    m = re.search(r"minsup_([0-9]+(?:\.[0-9]+)?)", filename)
    return float(m.group(1)) if m else None


def evaluate_itemsets_class_purity(
    itemsets: list[tuple[frozenset[int], int]],
    all_txs: list[frozenset[int]],
    img_classes: list[str],
    denom: int,
) -> pd.DataFrame:
    """Tính phân phối lớp và độ tinh khiết (purity) trên toàn bộ 600 ảnh cho mỗi closed itemset."""
    rows = []
    for iset, sup_file in itemsets:
        cls_counts = {c: 0 for c in TARGET_CLASSES}
        for tx, c in zip(all_txs, img_classes):
            if iset.issubset(tx):
                cls_counts[c] += 1
        total_all = sum(cls_counts.values())
        top_cls = max(cls_counts, key=cls_counts.get)
        purity = (cls_counts[top_cls] / total_all) if total_all > 0 else 0.0
        rows.append(
            {
                "word_ids": " ".join(str(w) for w in sorted(iset)),
                "length": len(iset),
                "sup_in_scope": sup_file,
                "sup_in_scope_pct": round(sup_file / denom * 100.0, 2),
                "total_all_600": total_all,
                "airplanes_cnt": cls_counts["airplanes"],
                "motorbikes_cnt": cls_counts["motorbikes"],
                "faces_easy_cnt": cls_counts["faces_easy"],
                "top_class": top_cls,
                "purity_pct": round(purity * 100.0, 1),
            }
        )
    df = pd.DataFrame(rows)
    if not df.empty:
        df = df.sort_values(["sup_in_scope", "purity_pct", "length"], ascending=[False, False, False]).reset_index(
            drop=True
        )
    return df


def plot_itemset_patches(
    df_top: pd.DataFrame,
    word_stats: pd.DataFrame,
    title: str,
    save_path: Path,
    max_rows: int = 5,
) -> None:
    """Hiển thị mỗi hàng là 1 Closed Itemset, mỗi cột là ảnh lưới patch 3x3 của 1 Visual Word."""
    df_show = df_top.head(max_rows).reset_index(drop=True)
    if df_show.empty:
        return

    stats_map = word_stats.set_index("word_id").to_dict(orient="index")
    n_rows = len(df_show)
    max_cols = max(len(str(w).split()) for w in df_show["word_ids"])
    max_cols = max(max_cols, 2)

    fig, axes = plt.subplots(
        n_rows,
        max_cols,
        figsize=(max_cols * 3.0 + 1.5, n_rows * 3.1 + 0.8),
        squeeze=False,
    )
    fig.suptitle(title, fontsize=13, fontweight="bold", y=0.995)

    for r_idx, row in df_show.iterrows():
        words = [int(w) for w in str(row["word_ids"]).split()]
        row_label = (
            f"#{r_idx + 1} | {{{', '.join(map(str, words))}}}\n"
            f"Sup={row['sup_in_scope']} ({row['sup_in_scope_pct']}%)\n"
            f"Top: {row['top_class']}\nPurity: {row['purity_pct']}%"
        )
        for c_idx in range(max_cols):
            ax = axes[r_idx, c_idx]
            if c_idx < len(words):
                wid = words[c_idx]
                patch_path = PATCH_DIR / f"word_{wid:03d}.png"
                if patch_path.exists():
                    img = mpimg.imread(patch_path)
                    ax.imshow(img)
                else:
                    ax.text(0.5, 0.5, f"Missing\nword_{wid:03d}", ha="center", va="center")
                st = stats_map.get(wid, {})
                w_cls = st.get("top_class", "?")
                w_pur = float(st.get("top_class_purity", 0.0)) * 100.0
                ax.set_title(f"Word {wid}\n({w_cls}, {w_pur:.0f}%)", fontsize=9)
                ax.set_xticks([])
                ax.set_yticks([])
                if c_idx == 0:
                    ax.set_ylabel(row_label, fontsize=8.5, rotation=0, labelpad=65, va="center", ha="right")
            else:
                ax.axis("off")

    plt.tight_layout(rect=[0.12, 0.0, 1.0, 0.96])
    plt.savefig(save_path, dpi=200)
    plt.close(fig)


def plot_minsup_curves(df_summary: pd.DataFrame, save_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 4.8))
    for scope, grp in df_summary.groupby("scope"):
        grp_s = grp.sort_values("minsup", ascending=False)
        ax.plot(
            grp_s["minsup"] * 100,
            grp_s["closed_len_ge_2"],
            marker="o",
            linewidth=2,
            label=f"{scope} (len ≥ 2)",
        )
    ax.invert_xaxis()
    ax.set_xlabel("Ngưỡng minsup (%) — giảm dần từ trái sang phải")
    ax.set_ylabel("Số lượng Closed Itemsets (độ dài ≥ 2)")
    ax.set_title("Caltech-101: Ảnh hưởng của minsup lên số lượng Closed Itemsets")
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend()
    plt.tight_layout()
    plt.savefig(save_path, dpi=200)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description="Phân tích kết quả CHARM cho Caltech-101 Visual Words")
    parser.add_argument(
        "--split-classes",
        action="store_true",
        help="Tách transactions.txt thành 3 file theo từng lớp để chạy CHARM",
    )
    parser.add_argument(
        "--max-rows",
        type=int,
        default=5,
        help="Số closed itemsets hiển thị patch trong mỗi hình (mặc định: 5)",
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    FIG_DIR.mkdir(parents=True, exist_ok=True)

    if args.split_classes:
        split_transactions_by_class()
        return

    all_txs = load_transactions(TX_ALL_PATH)
    df_img = pd.read_csv(IMG_MAP_PATH)
    df_wstats = pd.read_csv(WORD_STATS_PATH)
    img_classes = df_img["class_name"].tolist()

    scopes = ["all"] + TARGET_CLASSES
    summary_rows = []
    files_by_scope: dict[str, dict[float, list[tuple[frozenset[int], int]]]] = {s: {} for s in scopes}

    for scope in scopes:
        pattern = f"charm_{scope}_minsup_*.txt"
        for fp in sorted(OUT_DIR.glob(pattern)):
            ms = extract_minsup(fp.name)
            if ms is None:
                continue
            isets = parse_charm_output(fp)
            files_by_scope[scope][ms] = isets
            len_ge_2 = [x for x in isets if len(x[0]) >= 2]
            summary_rows.append(
                {
                    "scope": scope,
                    "minsup": ms,
                    "total_closed": len(isets),
                    "closed_len_ge_2": len(len_ge_2),
                    "max_length": max((len(x[0]) for x in isets), default=0),
                    "file": fp.name,
                }
            )

    if not summary_rows:
        print(f"[CẢNH BÁO] Chưa tìm thấy file charm_<scope>_minsup_*.txt trong {OUT_DIR}.")
        print("Hãy chạy các lệnh `julia src/main.jl ...` trước khi chạy script này.")
        return

    df_summary = pd.DataFrame(summary_rows).sort_values(["scope", "minsup"], ascending=[True, False])
    print("\n=== 1. TỔNG HỢP KẾT QUẢ CHARM TRÊN CALTECH-101 ===")
    print(df_summary.to_string(index=False))
    df_summary.to_csv(OUT_DIR / "caltech_minsup_summary.csv", index=False, encoding="utf-8-sig")

    if len(df_summary) >= 2:
        plot_minsup_curves(df_summary, FIG_DIR / "fig1_caltech_minsup_curve.png")

    # Phân tích chi tiết & vẽ patch cho từng phạm vi (all + 3 lớp)
    for scope in scopes:
        if not files_by_scope[scope]:
            continue
        # Chọn mức minsup thấp nhất có ít nhất 1 itemset len >= 2
        valid_ms = [
            ms for ms, isets in files_by_scope[scope].items() if any(len(x[0]) >= 2 for x in isets)
        ]
        if not valid_ms:
            print(f"\n[LƯU Ý] Phạm vi '{scope}' chưa có closed itemset độ dài >= 2 (hãy thử giảm minsup).")
            continue
        target_ms = min(valid_ms)
        multi_isets = [x for x in files_by_scope[scope][target_ms] if len(x[0]) >= 2]
        denom = len(all_txs) if scope == "all" else sum(1 for c in img_classes if c == scope)

        df_eval = evaluate_itemsets_class_purity(multi_isets, all_txs, img_classes, denom)
        df_eval.to_csv(OUT_DIR / f"top_visual_itemsets_{scope}.csv", index=False, encoding="utf-8-sig")

        print(f"\n=== 2. TOP 10 CLOSED ITEMSETS (len >= 2) — PHẠM VI: {scope.upper()} (minsup={target_ms}) ===")
        print(df_eval.head(10).to_string(index=False))

        # Vẽ lưới patch cho Top itemsets phổ biến nhất
        fig_path = FIG_DIR / f"fig_patches_{scope}.png"
        plot_itemset_patches(
            df_eval,
            df_wstats,
            title=f"Top Closed Itemsets (len ≥ 2) — {scope.upper()} (minsup={target_ms})",
            save_path=fig_path,
            max_rows=args.max_rows,
        )
        print(f"  -> Đã lưu hình lưới patch: {fig_path}")

    print(f"\n[DONE] Toàn bộ bảng CSV & hình ảnh đã lưu tại: {OUT_DIR}")


if __name__ == "__main__":
    main()