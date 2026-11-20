"""
Ứng dụng 1: Phân tích Closed Frequent Itemsets trên Web Server Access Logs
- Đọc kết quả chạy CHARM của nhóm (src/main.jl) ở nhiều mức minsup.
- Ánh xạ ngược ItemID -> EventName từ mapping.csv.
- Liệt kê Top Closed Itemsets (len >= 2) kèm support và template sự kiện.
- So sánh tần suất giữa phiên bình thường (Normal) và phiên bất thường (Anomalous/Bot/Scan/Error).
- Xuất bảng CSV và biểu đồ phục vụ báo cáo.

Cách chạy (từ thư mục gốc Group_12_Charm):
  1) Xuất tách file normal/anomaly (tùy chọn nếu muốn chạy CHARM riêng trên tập bất thường):
       python scripts/analyze_web_logs.py --export-split
  2) Phân tích & vẽ biểu đồ sau khi đã chạy CHARM:
       python scripts/analyze_web_logs.py
"""

import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# ==============================================================================
# CẤU HÌNH ĐƯỜNG DẪN (khớp với cấu trúc dự án Group_12_Charm)
# ==============================================================================
PRE_DIR = Path("data/application/web_server_access_logs/pre_process")
TX_PATH = PRE_DIR / "transaction.txt"
MAP_PATH = PRE_DIR / "mapping.csv"

OUT_DIR = Path("results/application/web_server_access_logs")
FIG_DIR = OUT_DIR / "figures"

# Từ khóa nhận diện phiên bất thường / bot / scan / lỗi dựa trên các tag đã mã hóa
# trong web_server_acess_log.ipynb
ANOMALY_EXACT_TAGS = {
    "BEHAVIOR_4XX_SCANNING_BURST",
    "BEHAVIOR_NO_ASSET_SCRAPING",
    "RATE_EXTREME_FLOOD",
    "UA_EMPTY",
    "UA_KNOWN_BOT",
}
ANOMALY_SUBSTRINGS = (
    "SCAN_DB_ADMIN",
    "SCAN_CMS_ADMIN",
    "SCAN_EXPLOIT_VULN",
    "UNKNOWN_SCAN_PATH",
    "MALFORMED_PROBE",
    "INVALID_URI_TYPO",
    "_400",
    "_403",
    "_404",
    "_500",
    "_502",
    "_503",
)


def load_mapping(map_path: Path) -> tuple[dict[int, str], dict[str, int]]:
    df = pd.read_csv(map_path)
    id_col, name_col = df.columns[0], df.columns[1]
    id_to_event = {int(r[id_col]): str(r[name_col]) for _, r in df.iterrows()}
    event_to_id = {v: k for k, v in id_to_event.items()}
    return id_to_event, event_to_id


def get_anomaly_item_ids(id_to_event: dict[int, str]) -> set[int]:
    anomaly_ids = set()
    for item_id, name in id_to_event.items():
        if name in ANOMALY_EXACT_TAGS or any(sub in name for sub in ANOMALY_SUBSTRINGS):
            anomaly_ids.add(item_id)
    return anomaly_ids


def parse_charm_output(path: Path) -> list[tuple[frozenset[int], int]]:
    """Đọc file kết quả CHARM định dạng SPMF: '<id1> <id2> ... #SUP: <count>'."""
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


def extract_minsup_from_name(filename: str) -> float | None:
    m = re.search(r"minsup_([0-9]+(?:\.[0-9]+)?)", filename)
    return float(m.group(1)) if m else None


def export_normal_anomaly_split(tx_path: Path, anomaly_ids: set[int]) -> None:
    normal_out = PRE_DIR / "transaction_normal.txt"
    anomaly_out = PRE_DIR / "transaction_anomaly.txt"
    n_norm = 0
    n_anom = 0
    with (
        open(tx_path, "r", encoding="utf-8") as fin,
        open(normal_out, "w", encoding="utf-8") as f_norm,
        open(anomaly_out, "w", encoding="utf-8") as f_anom,
    ):
        for line in fin:
            s = line.strip()
            if not s:
                continue
            items = {int(x) for x in s.split()}
            if items & anomaly_ids:
                f_anom.write(s + "\n")
                n_anom += 1
            else:
                f_norm.write(s + "\n")
                n_norm += 1
    total = n_norm + n_anom
    print(f"[DONE] Đã tách transaction.txt ({total:,} phiên):")
    print(f"  - Normal   : {n_norm:,} ({n_norm / total * 100:.2f}%) -> {normal_out}")
    print(f"  - Anomalous: {n_anom:,} ({n_anom / total * 100:.2f}%) -> {anomaly_out}")


def compare_normal_vs_anomaly(
    tx_path: Path,
    candidate_itemsets: list[tuple[frozenset[int], int]],
    anomaly_ids: set[int],
    id_to_event: dict[int, str],
) -> tuple[pd.DataFrame, int, int]:
    """Đếm tần suất xuất hiện của từng closed itemset trên phiên Bình thường vs Bất thường."""
    norm_counts = [0] * len(candidate_itemsets)
    anom_counts = [0] * len(candidate_itemsets)
    n_norm = 0
    n_anom = 0

    with open(tx_path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            tx = frozenset(int(x) for x in s.split())
            is_anom = not tx.isdisjoint(anomaly_ids)
            if is_anom:
                n_anom += 1
                for idx, (iset, _) in enumerate(candidate_itemsets):
                    if iset.issubset(tx):
                        anom_counts[idx] += 1
            else:
                n_norm += 1
                for idx, (iset, _) in enumerate(candidate_itemsets):
                    if iset.issubset(tx):
                        norm_counts[idx] += 1

    total = n_norm + n_anom
    rows = []
    for idx, (iset, sup_all) in enumerate(candidate_itemsets):
        c_norm = norm_counts[idx]
        c_anom = anom_counts[idx]
        r_all = sup_all / total * 100.0
        r_norm = c_norm / max(n_norm, 1) * 100.0
        r_anom = c_anom / max(n_anom, 1) * 100.0
        # Tỷ lệ làm giàu (Enrichment / Lift tương đối về phía bất thường)
        ratio_anom_vs_norm = (r_anom / r_norm) if r_norm > 0 else float("inf")
        events = sorted(id_to_event.get(i, str(i)) for i in iset)
        rows.append(
            {
                "item_ids": " ".join(str(i) for i in sorted(iset)),
                "event_templates": " + ".join(events),
                "length": len(iset),
                "sup_all": sup_all,
                "sup_all_pct": round(r_all, 3),
                "sup_normal": c_norm,
                "sup_normal_pct": round(r_norm, 3),
                "sup_anomaly": c_anom,
                "sup_anomaly_pct": round(r_anom, 3),
                "anom_to_norm_ratio": round(ratio_anom_vs_norm, 2)
                if np.isfinite(ratio_anom_vs_norm)
                else 999.0,
            }
        )

    df_cmp = pd.DataFrame(rows).sort_values("sup_all", ascending=False).reset_index(drop=True)
    return df_cmp, n_norm, n_anom


def plot_minsup_curve(df_summary: pd.DataFrame, save_path: Path) -> None:
    df_s = df_summary.sort_values("minsup", ascending=False)
    fig, ax = plt.subplots(figsize=(7.5, 4.5))
    ax.plot(
        df_s["minsup"] * 100,
        df_s["total_closed"],
        marker="o",
        linewidth=2,
        label="Tất cả Closed Itemsets",
    )
    ax.plot(
        df_s["minsup"] * 100,
        df_s["closed_len_ge_2"],
        marker="s",
        linewidth=2,
        linestyle="--",
        label="Closed Itemsets (độ dài ≥ 2)",
    )
    ax.invert_xaxis()
    ax.set_xlabel("Ngưỡng minsup (%) — giảm dần từ trái sang phải")
    ax.set_ylabel("Số lượng Closed Itemsets")
    ax.set_title("Web Server Logs: Số lượng Closed Itemsets theo minsup")
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend()
    plt.tight_layout()
    plt.savefig(save_path, dpi=200)
    plt.close(fig)


def plot_normal_vs_anomaly(df_cmp: pd.DataFrame, save_path: Path, top_k: int = 12) -> None:
    df_top = df_cmp.head(top_k).iloc[::-1]
    labels = [
        (s[:58] + "...") if len(s) > 60 else s for s in df_top["event_templates"].tolist()
    ]
    y = np.arange(len(labels))
    h = 0.36

    fig, ax = plt.subplots(figsize=(11, max(5.5, top_k * 0.55)))
    ax.barh(y + h / 2, df_top["sup_normal_pct"], height=h, label="Phiên bình thường (Normal)", color="#2b7bba")
    ax.barh(y - h / 2, df_top["sup_anomaly_pct"], height=h, label="Phiên bất thường (Anomaly/Bot/Scan)", color="#d95f02")
    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=8.5)
    ax.set_xlabel("Tần suất xuất hiện trong nhóm phiên (%)")
    ax.set_title(f"So sánh tần suất Top {top_k} Closed Itemsets (len ≥ 2): Normal vs. Anomalous")
    ax.grid(True, axis="x", linestyle=":", alpha=0.6)
    ax.legend()
    plt.tight_layout()
    plt.savefig(save_path, dpi=200)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description="Phân tích kết quả CHARM cho Web Server Access Logs")
    parser.add_argument(
        "--export-split",
        action="store_true",
        help="Tách transaction.txt thành transaction_normal.txt và transaction_anomaly.txt",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=30,
        help="Số lượng closed itemsets (len >= 2) đưa vào so sánh Normal vs Anomaly (mặc định: 30)",
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    FIG_DIR.mkdir(parents=True, exist_ok=True)

    id_to_event, _ = load_mapping(MAP_PATH)
    anomaly_ids = get_anomaly_item_ids(id_to_event)
    print(f"Đã nạp {len(id_to_event)} items từ {MAP_PATH} ({len(anomaly_ids)} item gắn cờ bất thường/bot/lỗi).")

    if args.export_split:
        export_normal_anomaly_split(TX_PATH, anomaly_ids)
        return

    # 1. Quét tất cả file kết quả CHARM trong output/
    charm_files = sorted(OUT_DIR.glob("charm_minsup_*.txt"))
    if not charm_files:
        print(f"[CẢNH BÁO] Chưa tìm thấy file charm_minsup_*.txt trong {OUT_DIR}.")
        print("Hãy chạy các lệnh `julia src/main.jl ...` trước khi chạy script này.")
        return

    summary_rows = []
    parsed_by_minsup: dict[float, list[tuple[frozenset[int], int]]] = {}

    # Đếm tổng số giao dịch
    with open(TX_PATH, "r", encoding="utf-8") as f:
        total_tx = sum(1 for line in f if line.strip())

    for fp in charm_files:
        ms = extract_minsup_from_name(fp.name)
        if ms is None:
            continue
        itemsets = parse_charm_output(fp)
        parsed_by_minsup[ms] = itemsets
        len_ge_2 = [x for x in itemsets if len(x[0]) >= 2]
        max_len = max((len(x[0]) for x in itemsets), default=0)
        summary_rows.append(
            {
                "minsup": ms,
                "minsup_count": int(np.ceil(ms * total_tx)),
                "total_closed": len(itemsets),
                "closed_len_ge_2": len(len_ge_2),
                "max_length": max_len,
                "file": fp.name,
            }
        )

    df_summary = pd.DataFrame(summary_rows).sort_values("minsup", ascending=False)
    print("\n=== 1. TỔNG HỢP KẾT QUẢ CHARM THEO CÁC MỨC MINSUP ===")
    print(df_summary.to_string(index=False))
    df_summary.to_csv(OUT_DIR / "minsup_summary.csv", index=False, encoding="utf-8-sig")

    if len(df_summary) >= 2:
        plot_minsup_curve(df_summary, FIG_DIR / "fig1_minsup_vs_itemsets.png")

    # 2. Chọn mức minsup thấp nhất (nhiều mẫu phong phú nhất) để liệt kê Top & so sánh
    target_ms = min(parsed_by_minsup.keys())
    all_isets = parsed_by_minsup[target_ms]
    multi_isets = sorted(
        [x for x in all_isets if len(x[0]) >= 2],
        key=lambda x: (-x[1], -len(x[0])),
    )

    print(f"\n=== 2. TOP 15 CLOSED ITEMSETS (len >= 2) TẠI minsup = {target_ms} ===")
    for rank, (iset, sup) in enumerate(multi_isets[:15], 1):
        ev_str = " + ".join(sorted(id_to_event.get(i, str(i)) for i in iset))
        print(f"{rank:2d}. [sup={sup:,} | {sup/total_tx*100:.2f}% | len={len(iset)}] {ev_str}")

    # 3. So sánh Normal vs Anomalous cho Top-K itemsets (len >= 2)
    # Lấy thêm các itemset chứa cờ bất thường nếu chưa nằm trong top-K đầu
    top_candidates = list(multi_isets[: args.top_k])
    seen = {iset for iset, _ in top_candidates}
    anom_specific = [x for x in multi_isets if (x[0] & anomaly_ids) and x[0] not in seen][:15]
    candidates = top_candidates + anom_specific

    print(f"\nĐang quét {TX_PATH} để so sánh Normal vs. Anomalous trên {len(candidates)} closed itemsets...")
    df_cmp, n_norm, n_anom = compare_normal_vs_anomaly(TX_PATH, candidates, anomaly_ids, id_to_event)
    df_cmp.to_csv(OUT_DIR / "normal_vs_anomaly_comparison.csv", index=False, encoding="utf-8-sig")

    print(f"\nPhân nhóm phiên (tổng {n_norm + n_anom:,}):")
    print(f"  - Normal   : {n_norm:,} ({n_norm/(n_norm+n_anom)*100:.2f}%)")
    print(f"  - Anomalous: {n_anom:,} ({n_anom/(n_norm+n_anom)*100:.2f}%)")

    print("\n=== 3A. TOP 10 MẪU PHỔ BIẾN NHẤT (NORMAL vs ANOMALY) ===")
    cols = ["length", "sup_all_pct", "sup_normal_pct", "sup_anomaly_pct", "anom_to_norm_ratio", "event_templates"]
    print(df_cmp[cols].head(10).to_string(index=False))

    df_anom_enriched = df_cmp[df_cmp["anom_to_norm_ratio"] >= 1.5].sort_values(
        ["sup_anomaly_pct", "anom_to_norm_ratio"], ascending=[False, False]
    )
    print("\n=== 3B. TOP 10 MẪU ĐẶC TRƯNG CHO PHIÊN BẤT THƯỜNG / BOT / SCAN ===")
    print(df_anom_enriched[cols].head(10).to_string(index=False))

    plot_normal_vs_anomaly(df_cmp, FIG_DIR / "fig2_normal_vs_anomaly.png", top_k=12)
    print(f"\n[DONE] Đã lưu CSV & biểu đồ tại: {OUT_DIR}")


if __name__ == "__main__":
    main()