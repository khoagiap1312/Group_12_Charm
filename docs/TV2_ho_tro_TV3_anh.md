# Hỗ trợ của TV2 cho ứng dụng ảnh (Caltech-101, visual words)

Dữ liệu: `data/application/cal_tech_101/pre_process/transactions.txt`, gồm 600 giao dịch (mỗi ảnh một giao dịch),
300 visual word (k = 300), độ dài giao dịch trung bình 47,9 (tối đa 57). Độ dày khoảng 16% (47,9 / 300), cùng loại
"dày vừa" với Mushroom, nên CHARM bản `optimized` phù hợp.

## 1. Tính đúng

Baseline và Optimized đều khớp 100% với SPMF (`scripts/benchmark.jl compare`), không thiếu, không thừa, không sai
support, ở các mức minsup 0,10; 0,07; 0,05; 0,03; 0,02.

## 2. Số tập đóng và thời gian theo minsup (toàn bộ 600 ảnh)

Thời gian thuật toán `fit!` (ms) từ một lần chạy `src/main.jl -w 1`, không phải trung vị 3 lần, nên chỉ dùng để chọn
minsup. Mức 0,07 chỉ đo số tập đóng và tính đúng, chưa đo thời gian.

| minsup | minsup count | Số tập đóng | Baseline (ms) | Optimized (ms) | Ghi chú |
|---|---|---|---|---|---|
| 0,10 | 60 | 294 | 71 | 5 | đủ nhỏ để đọc bằng tay |
| 0,07 | 42 | 371 | | | |
| 0,05 | 30 | 1.540 | 76 | 8 | |
| 0,03 | 18 | 15.845 | 362 | 108 | quá nhiều để xem từng cái |
| 0,02 | 12 | 42.616 | 1.653 | 491 | |
| 0,01 | 6 | 456.257 | 7.316 | 5.087 | ghi file 1,3 s, RAM 435 đến 598 MB |

## 3. Gợi ý chọn tham số

- **minsup 0,05 đến 0,10** (30 đến 60 ảnh) cho 294 đến 1.540 tập đóng: vừa đủ để xếp hạng và vẽ lưới patch.
  Mức 0,03 trở xuống cho hàng chục nghìn tập, phần lớn là các tập con của cùng một nhóm patch.
- **Không hạ xuống 0,01**: 456 nghìn tập đóng, Optimized chỉ nhanh hơn Baseline 1,4 lần và dùng RAM nhiều hơn
  (598 so với 435 MB), như đã phân tích ở mục 2.8 của báo cáo (tidset đã thưa).
- Theo từng lớp (khoảng 200 ảnh mỗi lớp), nên đặt minsup cao hơn (0,08 đến 0,15) vì mỗi lớp ít giao dịch hơn;
  mức TV3 đang dùng nằm đúng khoảng này.
- Nếu muốn giảm số tập cần xem mà không đổi minsup, lọc theo độ dài (≥ 2) và độ tinh khiết lớp như
  `scripts/analyze_caltech101.py` đang làm.
- Nên chạy bằng `--algo optimized`; thêm `--order support_asc` không cần thiết ở quy mô này.

## 4. Lưu ý cho báo cáo của TV3

- Số liệu mục 2 chỉ chạy một lần mỗi cấu hình; nếu đưa vào báo cáo, cần chạy lại 3 lần lấy trung vị
  (`scripts/benchmark.jl` hiện chỉ hỗ trợ các tập có tên trong `DATASETS`).
- Nếu đổi k hoặc thay `transactions.txt`, cần chạy lại bảng này, vì số tập đóng nhạy với k.
