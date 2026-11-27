# **Ứng dụng thực tế của thuật toán CHARM**

# **Ứng dụng 2: Khai phá mẫu trực quan (Visual Patterns) trên tập ảnh Caltech-101**

## **1. Mô tả tập dữ liệu và quy trình chuyển đổi ảnh sang giao dịch SPMF**

**Nguồn dữ liệu và tập con thực nghiệm**

Thực nghiệm sử dụng tập dữ liệu ảnh phân lớp đối tượng Caltech-101 (tải từ kho Hugging Face flwrlabs/caltech101, phân tập train). Nhằm đánh giá khả năng phát hiện mẫu trực quan đặc trưng giữa các nhóm đối tượng có cấu trúc hình học và kết cấu bề mặt khác biệt, nghiên cứu chọn lọc 3 lớp đại diện gồm: `airplanes` (máy bay), `motorbikes` (xe máy) và `faces_easy` (khuôn mặt chính diện). Với mỗi lớp, lấy mẫu ngẫu nhiên cố định 200 ảnh (`SEED = 0`), tạo thành tập thực nghiệm cân bằng gồm tổng cộng 600 ảnh.

**Quy trình chuyển đổi dữ liệu (Image-to-Transaction Pipeline)**

Toàn bộ quy trình tiền xử lý được cài đặt tái lập trong notebook notebooks/caltech\_101.ipynb (sử dụng thư viện OpenCV và scikit-learn cho bước trích xuất đặc trưng và học từ điển thị giác; phần khai phá tập mục đóng phổ biến sử dụng hoàn toàn thuật toán CHARM do nhóm tự cài đặt bằng ngôn ngữ Julia). Quy trình gồm 5 bước:

1. **Chuẩn hóa kích thước ảnh:** Thay đổi kích thước (resize) mỗi ảnh sao cho cạnh dài nhất bằng 300 pixel (`MAX_IMG_SIDE = 300`), giữ nguyên tỷ lệ khung hình nhằm đảm bảo mật độ điểm đặc trưng đồng nhất giữa các ảnh.  
2. **Trích xuất đặc trưng cục bộ RootSIFT:** Sử dụng thuật toán SIFT (`cv2.SIFT_create(nfeatures=60)`) để trích xuất tối đa 60 điểm đặc trưng (keypoints) nổi bật nhất trên mỗi ảnh, sau đó chuyển đổi vector mô tả 128 chiều sang dạng RootSIFT (chuẩn hóa L1 kết hợp lấy căn bậc hai phần tử) nhằm tăng tính bền vững khi so sánh khoảng cách Euclid. Kết quả thu được tổng cộng 35.968 vector RootSIFT (128 chiều), trung bình 59,9 keypoints/ảnh (tối thiểu 49, tối đa 60, không có ảnh nào bị rỗng đặc trưng).  
3. **Học từ điển thị giác (Visual Codebook):** Gom cụm toàn bộ 35.968 vector RootSIFT bằng thuật toán K-Means (`sklearn.cluster.KMeans` với `K_CLUSTERS = 300`, `random_state = 0`, `n_init = 10`). Mô hình hội tụ với tổng bình phương khoảng cách trong cụm (inertia) bằng 6.460,88 và sử dụng trọn vẹn cả 300/300 từ thị giác (Visual Word ID đánh số từ 1 đến 300). Từ điển được lưu trữ tại `codebook_kmeans.joblib`.  
4. **Biểu diễn Bag-of-Visual-Words (BoVW) chuẩn SPMF:** Mỗi ảnh được ánh xạ thành một giao dịch gồm tập hợp các Visual Word ID không trùng lặp, sắp xếp tăng dần, xuất ra tệp `transactions.txt` (kèm ánh xạ ảnh – lớp `image_mapping.csv` và thống kê từng từ `visual_word_stats.csv`).  
5. **Trích xuất lưới patch đại diện:** Với mỗi visual word từ 1 đến 300, chọn tối đa 9 patch ảnh gốc kích thước 48 × 48 pixel (`PATCH_SIZE = 48`, `TOP_K_PATCHES = 9`) có vector RootSIFT gần tâm cụm nhất (cắt từ 587 ảnh nguồn), ghép thành lưới ảnh 3 × 3 và lưu tại `patches/word_001.png` đến `patches/word_300.png` để phục vụ trực quan hóa.

**Thống kê cơ sở dữ liệu giao dịch Caltech-101**

*Bảng 3.3: Thống kê đặc trưng cơ sở dữ liệu giao dịch Visual Words trên Caltech-101 (tệp transactions.txt)*

\| Phạm vi / Lớp \| Số giao dịch (\|D\|) \| Số mục (\|I\|) \| Độ dài TB ± Độ lệch chuẩn \| Độ dài nhỏ nhất (Min) \| Độ dài trung vị (Median) \| Độ dài lớn nhất (Max) \| Độ dày ma trận (%) \|  
\|---\|---\|---\|---\|---\|---\|---\|---\|---\|---\|---\|---\|  
\| **Toàn bộ (all)** \| 600 \| 300 \| 47,92 ± 4,52 \| 28 \| 48 \| 57 \| 15,97% \|  
\| **airplanes** \| 200 \| 300 \| 46,94 \| 33 \| — \| 57 \| 15,65% \|  
\| **motorbikes** \| 200 \| 300 \| 48,17 \| 36 \| — \| 57 \| 16,06% \|  
\| **faces\_easy** \| 200 \| 300 \| 48,66 \| 28 \| — \| 56 \| 16,22% \|

*Nhận xét:* Độ dài giao dịch giữa 3 lớp rất đồng đều (dao động quanh 46,9–48,7 visual words/ảnh), với độ dày ma trận tổng thể đạt 15,97% (mức trung bình – cao so với dữ liệu giỏ hàng thưa thông thường). Nhờ giới hạn tối đa 60 keypoints/ảnh, sự chênh lệch về độ phức tạp nền ảnh không gây thiên lệch quá lớn về độ dài giao dịch giữa các lớp.

---

## **2. Thiết lập thực nghiệm và ảnh hưởng của ngưỡng minsup**

Cấu hình khai phá CHARM theo 2 chiến lược phạm vi

Thuật toán CHARM phiên bản tối ưu (-a optimized) tự cài đặt bằng Julia (src/main.jl) được thực thi trên 2 phạm vi song song nhằm đánh giá toàn diện:

* **Phạm vi toàn bộ (all, 600 ảnh):** Chạy CHARM trên `transactions.txt` ở 4 mức ngưỡng minsup giảm dần: 10% (0,10), 7% (0,07), 5% (0,05) và 3% (0,03).  
* **Phạm vi theo từng lớp (per-class, 200 ảnh/lớp):** Dùng kịch bản `scripts/analyze_caltech101.py --split-classes` tách thành 3 tệp `transactions_airplanes.txt`, `transactions_motorbikes.txt` và `transactions_faces_easy.txt`, sau đó chạy CHARM trên từng lớp ở 3 mức ngưỡng minsup: 15% (0,15), 10% (0,10) và 8% (0,08).

*Bảng 3.4: Tổng hợp kết quả khai phá Closed Itemsets của CHARM theo phạm vi và ngưỡng minsup (nguồn: caltech\_minsup\_summary.csv)*

| Phạm vi (Scope) | Ngưỡng minsup (%) | Ngưỡng tuyệt đối (số ảnh) | Tổng Closed Itemsets | Closed Itemsets (độ dài ≥ 2\) | Độ dài lớn nhất (max\_length) |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **all (600 ảnh)** | 10,0% (0,10) | 60 | 294 | 3 | 2 |
| **all (600 ảnh)** | 7,0% (0,07) | 42 | 371 | 73 | 2 |
| **all (600 ảnh)** | 5,0% (0,05) | 30 | 1.540 | 1.240 | 3 |
| **all (600 ảnh)** | 3,0% (0,03) | 18 | 15.845 | 15.545 | 5 |
| **airplanes (200 ảnh)** | 15,0% (0,15) | 30 | 180 | 14 | 3 |
| **airplanes (200 ảnh)** | 10,0% (0,10) | 20 | 479 | 248 | 3 |
| **airplanes (200 ảnh)** | 8,0% (0,08) | 16 | 1.117 | 865 | 4 |
| **faces\_easy (200 ảnh)** | 15,0% (0,15) | 30 | 235 | 74 | 3 |
| **faces\_easy (200 ảnh)** | 10,0% (0,10) | 20 | 850 | 602 | 4 |
| **faces\_easy (200 ảnh)** | 8,0% (0,08) | 16 | 1.830 | 1.566 | 5 |
| **motorbikes (200 ảnh)** | 15,0% (0,15) | 30 | 252 | 101 | 3 |
| **motorbikes (200 ảnh)** | 10,0% (0,10) | 20 | 1.147 | 931 | 4 |
| **motorbikes (200 ảnh)** | 8,0% (0,08) | 16 | 2.640 | 2.405 | 5 |

*\[Vị trí chèn Hình 3.3: Biểu đồ ảnh hưởng của ngưỡng minsup lên số lượng Closed Itemsets (độ dài ≥ 2\) theo từng phạm vi trên Caltech-101 — tệp fig1\_caltech\_minsup\_curve.png\]*

**Nhận xét về ảnh hưởng của ngưỡng minsup và sự khác biệt giữa các lớp**

1. **Hiện tượng bùng nổ tổ hợp trên tập toàn bộ (all):** Ở minsup \= 10% (≥ 60/600 ảnh), hầu hết kết quả là các visual word đơn lẻ (291/294 tập), chỉ có đúng 3 closed itemset có độ dài ≥ 2\. Lý do là mỗi lớp chỉ chiếm đúng 1/3 (33,3%) tổng số ảnh, nên một tổ hợp đặc trưng riêng của 1 lớp muốn đạt 10% toàn tập phải xuất hiện ở tối thiểu 30% số ảnh của riêng lớp đó. Khi hạ minsup xuống 5% và 3%, số lượng tập đóng có độ dài ≥ 2 bùng nổ mạnh từ 3 lên 1.240 (ở 5%) và 15.545 (ở 3% — gấp 5.181 lần), đồng thời độ dài cực đại tăng từ 2 lên 5\.  
2. **So sánh mật độ đồng xuất hiện giữa 3 lớp ở cùng ngưỡng minsup \= 8% (≥ 16/200 ảnh):**  
   * `motorbikes` phát sinh số lượng closed itemset lớn nhất (2.640 tổng; 2.405 tập có độ dài ≥ 2; max\_length \= 5).  
   * `faces_easy` đứng thứ hai (1.830 tổng; 1.566 tập có độ dài ≥ 2; max\_length \= 5).  
   * `airplanes` có số lượng ít nhất (1.117 tổng; 865 tập có độ dài ≥ 2; max\_length \= 4).

   

   *Nguyên nhân:* Xuất phát từ tính đồng nhất hình học nội lớp: ảnh xe máy (chụp ngang, lặp lại cấu trúc bánh xe, nan hoa, khung sườn) và ảnh khuôn mặt chính diện (bố cục mắt – mũi – miệng – đường viền ổn định) tạo ra nhiều cụm đặc trưng RootSIFT lặp lại nhất quán hơn so với ảnh máy bay vốn biến thiên mạnh về góc nghiêng, tỷ lệ thân và nền trời/đường băng.

---

## **3. Phân tích Top Closed Itemsets và độ tinh khiết theo lớp (Class Purity)**

**Định nghĩa chỉ số độ tinh khiết theo lớp (Class Purity)**

Để đánh giá mức độ đặc trưng phân biệt của mỗi tập mục đóng \$X\$ (có độ dài ≥ 2\) khai phá được, chương trình scripts/analyze\_caltech101.py đối chiếu sự xuất hiện của \$X\$ trên toàn bộ 600 ảnh ở cả 3 lớp (\$n\_{airplanes}\$, \$n\_{motorbikes}\$, \$n\_{faces\_easy}\$). Gọi \$N(X)\$ là tổng số ảnh chứa \$X\$ trong toàn bộ 600 ảnh, lớp chiếm ưu thế là lớp có số lượng xuất hiện lớn nhất, và độ tinh khiết được xác định bằng công thức:

\$\$\\text{Purity}(X) \= \\frac{\\max(n\_{airplanes}, n\_{motorbikes}, n\_{faces\_easy})}{N(X)} \\times 100%\$\$

Một closed itemset có Purity cao (90%–100%) đóng vai trò như một "chữ ký trực quan" (visual signature) đặc thù của một lớp đối tượng; ngược lại, Purity thấp (\~45%–55%) cho thấy đó là tổ hợp đặc trưng chung của nền ảnh (background clutter) hoặc biên cạnh phổ quát.

**Kết quả khai phá trên toàn bộ tập ảnh (all, minsup \= 3%)**

*Bảng 3.5: Top Closed Itemsets tiêu biểu trên toàn bộ 600 ảnh Caltech-101 ở minsup \= 3% (nguồn: top\_visual\_itemsets\_all.csv)*

| Hạng / Nhóm | Visual Word IDs | Độ dài | Support (số ảnh / %) | Phân bố (A / M / F) | Lớp chủ đạo | Độ tinh khiết (%) |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| **Top 1** | {45, 102} | 2 | 72 (12,00%) | 6 / 57 / 9 | motorbikes | 79,2% |
| **Top 2** | {63, 141} | 2 | 65 (10,83%) | 2 / 0 / 63 | faces\_easy | 96,9% |
| **Top 3** | {60, 93} | 2 | 62 (10,33%) | 3 / 42 / 17 | motorbikes | 67,7% |
| **Top 4** | {130, 141} | 2 | 56 (9,33%) | 0 / 1 / 55 | faces\_easy | 98,2% |
| **Top 5** | {56, 259} | 2 | 55 (9,17%) | 5 / 48 / 2 | motorbikes | 87,3% |
| **Mẫu tinh khiết cao (len=2)** | {13, 215} | 2 | 52 (8,67%) | 0 / 0 / 52 | faces\_easy | 100,0% |
| **Mẫu nền chung (nhiễu)** | {157, 191} | 2 | 55 (9,17%) | 26 / 12 / 17 | airplanes | 47,3% |
| **Mẫu nền chung (nhiễu)** | {54, 182} | 2 | 54 (9,00%) | 24 / 3 / 27 | faces\_easy | 50,0% |
| **Mẫu dài nhất (len=5)** | {26, 45, 56, 102, 259} | 5 | 18 (3,00%) | 0 / 18 / 0 | motorbikes | 100,0% |

**Kết quả khai phá riêng theo từng lớp (minsup \= 8%, ≥ 16/200 ảnh)**

*Bảng 3.6: So sánh các Closed Itemsets đặc trưng nhất khai phá riêng theo từng lớp ở minsup \= 8% (nguồn: top\_visual\_itemsets\_airplanes.csv, top\_visual\_itemsets\_faces\_easy.csv, top\_visual\_itemsets\_motorbikes.csv)*

| Lớp mục tiêu | Visual Word IDs | Độ dài | Support nội lớp (số ảnh / %) | Tổng trên 600 ảnh (A / M / F) | Độ tinh khiết (%) | Vai trò nhận diện |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| **airplanes** | {14, 200} | 2 | 43 (21,5%) | 49 (43 / 4 / 2\) | 87,8% | Cặp phổ biến nhất lớp |
| **airplanes** | {5, 200} | 2 | 38 (19,0%) | 41 (38 / 3 / 0\) | 92,7% | Đặc trưng mạnh |
| **airplanes** | {5, 268} | 2 | 31 (15,5%) | 31 (31 / 0 / 0\) | 100,0% | Cặp thuần khiết 100% |
| **airplanes** | {14, 200, 239} | 3 | 31 (15,5%) | 34 (31 / 2 / 1\) | 91,2% | Tổ hợp bậc 3 chủ đạo |
| **airplanes** | {5, 14, 200, 239} | 4 | 19 (9,5%) | 19 (19 / 0 / 0\) | 100,0% | Mẫu dài nhất (len=4), thuần khiết 100% |
| **faces\_easy** | {63, 141} | 2 | 63 (31,5%) | 65 (2 / 0 / 63\) | 96,9% | Cặp phổ biến nhất lớp |
| **faces\_easy** | {130, 141} | 2 | 55 (27,5%) | 56 (0 / 1 / 55\) | 98,2% | Đặc trưng rất cao |
| **faces\_easy** | {13, 215} | 2 | 52 (26,0%) | 52 (0 / 0 / 52\) | 100,0% | Cặp thuần khiết 100% |
| **faces\_easy** | {13, 85, 215} | 3 | 35 (17,5%) | 35 (0 / 0 / 35\) | 100,0% | Tổ hợp bậc 3 thuần khiết |
| **faces\_easy** | {46, 97, 141, 167, 242} | 5 | 16 (8,0%) | 16 (0 / 0 / 16\) | 100,0% | Mẫu dài nhất (len=5), thuần khiết 100% |
| **motorbikes** | {45, 102} | 2 | 57 (28,5%) | 72 (6 / 57 / 9\) | 79,2% | Cặp phổ biến nhất lớp |
| **motorbikes** | {56, 259} | 2 | 48 (24,0%) | 55 (5 / 48 / 2\) | 87,3% | Đặc trưng mạnh |
| **motorbikes** | {45, 56} | 2 | 40 (20,0%) | 43 (1 / 40 / 2\) | 93,0% | Lõi đặc trưng cao |
| **motorbikes** | {45, 102, 212} | 3 | 31 (15,5%) | 31 (0 / 31 / 0\) | 100,0% | Tổ hợp bậc 3 thuần khiết |
| **motorbikes** | {26, 45, 56, 102, 259} | 5 | 18 (9,0%) | 18 (0 / 18 / 0\) | 100,0% | Mẫu dài nhất (len=5), thuần khiết 100% |

**Diễn giải sâu các phát hiện từ dữ liệu**

1. **Cấu trúc cụm lõi đặc trưng (Visual Word Hubs) của từng lớp:**  
   * Lớp `faces_easy` đạt độ phân biệt cao nhất trong 3 lớp, hình thành 2 cụm đồng xuất hiện rất chặt chẽ xoay quanh `{141, 63, 130, 97, 46, 136, 167, 242}` và `{13, 85, 215}`. Ngay từ độ dài 2, các cặp như `{13, 215}` (52 ảnh) và `{97, 141}` (47 ảnh) đã đạt độ tinh khiết tuyệt đối 100%.  
   * Lớp `motorbikes` phân hóa rõ thành 2 nhóm: nhóm lõi đặc trưng mạnh xoay quanh `{45, 102, 56, 259, 212, 26, 70}` (đạt 93%–100% purity khi kết hợp) và nhóm trung gian `{60, 93, 106, 171}` có độ tinh khiết vừa phải (67,7%–76,4%) do chia sẻ một phần kết cấu tương đồng với ảnh lớp `faces_easy` (chẳng hạn `{60, 93}` xuất hiện ở 42 ảnh motorbikes và 17 ảnh faces\_easy).  
   * Lớp `airplanes` hội tụ quanh cụm lõi `{5, 14, 200, 239, 268, 291}`. Dù có tần suất thấp hơn hai lớp còn lại, các tổ hợp bậc 4 như `{5, 14, 200, 239}` (19 ảnh), `{14, 200, 239, 268}` (17 ảnh) và `{14, 200, 239, 291}` (16 ảnh) đều đạt độ tinh khiết tuyệt đối 100%.  
2. **Quy luật đánh đổi giữa Độ dài tập mục và Độ tinh khiết (Length–Purity Trade-off):** Một quy luật nhất quán xuất hiện ở cả 3 lớp là khi độ dài closed itemset tăng từ 2 lên 3–5, độ tinh khiết tăng mạnh và hội tụ về 100%, đánh đổi bằng độ hỗ trợ giảm xuống vùng 8%–9,5%. Chẳng hạn, ở motorbikes, cặp `{45, 102}` đạt support 28,5% nhưng chỉ tinh khiết 79,2% (lẫn 6 ảnh airplanes và 9 ảnh faces\_easy); khi mở rộng thêm 3 từ thị giác thành tổ hợp đóng độ dài 5 `{26, 45, 56, 102, 259}`, độ tinh khiết tăng lên 100,0% (18/18 ảnh đều là motorbikes). Điều này chứng minh khai phá tập mục đóng phổ biến có khả năng khử nhiễu đa nghĩa (polysemy) của từng visual word đơn lẻ rất hiệu quả.  
3. **Nhận diện mẫu nền chung (Background Patterns):** Khi chạy trên toàn tập `all`, các cặp như `{157, 191}` (support 9,17%, phân bố 26/12/17, purity 47,3%) và `{54, 182}` (support 9,00%, phân bố 24/3/27, purity 50,0%) có tần suất cao nhưng phân tán rộng giữa các lớp. Đây là các mẫu kết cấu nền hoặc biên cạnh phổ thông không mang giá trị phân lớp.

---

## **4. Trực quan hóa lưới Patch đại diện của các Visual Words**

Để kiểm chứng trực quan ý nghĩa thị giác đằng sau các mã số Visual Word ID, kịch bản `scripts/analyze_caltech101.py` tổng hợp lưới patch 3 × 3 đại diện cho Top 5 Closed Itemsets (độ dài ≥ 2\) ở mỗi phạm vi. Mỗi hàng tương ứng với một closed itemset (kèm thông số Support, Top Class, Purity), và mỗi cột hiển thị 9 patch 48 × 48 pixel gần tâm cụm nhất của một visual word thành phần.

Các hình kết quả tương ứng để chèn vào báo cáo LaTeX:

* *\[Vị trí chèn Hình 3.4: Lưới patch đại diện cho Top 5 Closed Itemsets trên toàn bộ 600 ảnh — tệp fig\_patches\_all.png\]*  
* *\[Vị trí chèn Hình 3.5: Lưới patch đại diện cho Top 5 Closed Itemsets lớp airplanes (minsup \= 8%) — tệp fig\_patches\_airplanes.png\]*  
* *\[Vị trí chèn Hình 3.6: Lưới patch đại diện cho Top 5 Closed Itemsets lớp faces\_easy (minsup \= 8%) — tệp fig\_patches\_faces\_easy.png\]*  
* *\[Vị trí chèn Hình 3.7: Lưới patch đại diện cho Top 5 Closed Itemsets lớp motorbikes (minsup \= 8%) — tệp fig\_patches\_motorbikes.png\]*

*\[Ghi chú bổ sung khi hoàn thiện bản LaTeX: Bổ sung 1–2 câu mô tả chi tiết hình thái thực tế quan sát được từ các lưới patch trên từng hình (ví dụ: cấu trúc vùng mắt/mũi/viền mặt trên faces\_easy, vành bánh xe/nan hoa/khung sườn trên motorbikes, đường biên cánh/thân máy bay trên airplanes) sau khi đối chiếu trực tiếp các tệp PNG.\]*

---

## **5. Thảo luận chuyên sâu: Ứng dụng, độ nhạy tham số (k, minsup) và hạn chế**

**Ý nghĩa mẫu hình đặc trưng và tiềm năng ứng dụng**

1. **Biểu diễn đặc trưng bậc trung (Mid-level Visual Phrases) cho Phân loại ảnh (Image Classification):** Mô hình Bag-of-Visual-Words truyền thống giả định các từ thị giác độc lập nhau, nên dễ nhầm lẫn khi một patch đơn lẻ xuất hiện ở nhiều loại vật thể. Các closed itemsets có độ dài 3–5 và độ tinh khiết 95%–100% đóng vai trò như các "cụm bộ phận cấu thành" (visual phrases) có tính phân biệt cao. Chúng có thể được đưa trực tiếp vào làm vector đặc trưng bổ sung cho các bộ phân loại tuyến tính (SVM, Logistic Regression) hoặc xây dựng bộ phân loại dựa trên luật kết hợp (Associative Classification) có khả năng giải thích trực quan rõ ràng (giải thích được vì sao ảnh được gán nhãn lớp nào dựa trên bộ patch đồng xuất hiện).  
2. **Tối ưu hóa Truy vấn ảnh theo nội dung (Content-Based Image Retrieval — CBIR):** Thay vì lập chỉ mục đảo (inverted index) trên từng visual word đơn lẻ vốn trả về nhiều ảnh nhiễu, hệ thống CBIR có thể lập chỉ mục trên các closed visual itemsets. Nhờ tính chất "đóng" của CHARM (loại bỏ hoàn toàn các tập con dư thừa có cùng tập ảnh hỗ trợ), bộ chỉ mục gọn nhẹ hơn đáng kể trong khi vẫn bảo toàn đầy đủ khả năng truy xuất các ảnh chứa cùng tổ hợp bộ phận đặc trưng.

**Phân tích ảnh hưởng của kích thước từ điển thị giác k và ngưỡng minsup**

1. **Ảnh hưởng của số cụm k trong K-Means (Codebook Size):**  
   * *Khi k quá nhỏ (ví dụ k \= 50–100):* Xảy ra hiện tượng lượng tử hóa thô (under-quantization), nhiều patch có hình dạng khác biệt từ các lớp khác nhau bị gom chung vào một visual word. Hậu quả là giao dịch trở nên quá dày, các itemset có độ tinh khiết thấp và dễ phát sinh bùng nổ tổ hợp.  
   * *Khi k quá lớn (ví dụ k \= 1.000–2.000):* Xảy ra hiện tượng phân mảnh quá mức (over-fragmentation), các patch tương đồng về mặt ngữ nghĩa bị tách sang nhiều ID khác nhau. Hậu quả là ma trận giao dịch quá thưa, độ hỗ trợ của các tổ hợp đồng xuất hiện giảm mạnh khiến CHARM khó tìm được itemset độ dài ≥ 3 ở các mức minsup hợp lý.  
   * *Đánh giá cấu hình:* Với quy mô 600 ảnh và 35.968 vector RootSIFT (\~60 keypoints/ảnh), lựa chọn \$k \= 300\$ mang lại điểm cân bằng tốt: cả 300/300 cụm đều được kích hoạt (không có cụm chết), độ dài giao dịch trung bình đạt 47,92 (độ dày 15,97%), vừa đủ nhỏ gọn để khai phá nhanh vừa đủ chi tiết để đạt độ tinh khiết 90%–100%.  
2. **Ảnh hưởng của ngưỡng minsup:**  
   * Ngưỡng minsup cao (10% trên toàn tập hoặc 15% theo lớp) chỉ giữ lại số ít mẫu phổ quát nhất, đảm bảo tốc độ chạy rất nhanh nhưng bỏ sót nhiều mẫu đặc trưng bậc cao (độ dài 3–5).  
   * Ngưỡng minsup thấp (3% trên toàn tập hoặc 8% theo lớp) giúp khám phá được các mẫu dài có độ tinh khiết 100%, song làm số lượng tập đóng tăng theo hàm mũ (từ 3 lên 15.545 trên tập `all`). Thực nghiệm cũng chỉ ra chiến lược chạy CHARM tách riêng theo từng lớp (minsup \= 8%–10%) kết hợp bước hậu kiểm Class Purity trên toàn tập giúp kiểm soát số lượng ứng viên tốt hơn nhiều so với chạy trực tiếp ở ngưỡng rất thấp trên toàn tập gộp.

**Hạn chế của phương pháp và hướng cải tiến**

1. **Bỏ qua cấu trúc không gian (Spatial Layout Ignorance):** Mô hình giao dịch BoVW chỉ xét sự đồng xuất hiện của các visual words trong cùng một khung ảnh mà không xét vị trí tương đối giữa chúng (ví dụ: mắt phải nằm phía trên mũi, hai bánh xe nằm ngang hàng). Hướng khắc phục là kết hợp chia lưới không gian (Spatial Pyramid Matching) hoặc chỉ gom cặp các visual words lân cận nhau trong bán kính không gian nhất định.  
2. **Mất thông tin tần suất lặp trong cùng một ảnh:** Định dạng giao dịch nhị phân SPMF chỉ ghi nhận sự có mặt/vắng mặt của mỗi visual word, bỏ qua việc một đặc trưng lặp lại nhiều lần trên cùng một đối tượng (như các nan hoa xe máy). Có thể mở rộng sang khai phá tập phổ biến có trọng số (Weighted/Quantitative FIM) hoặc sử dụng trọng số TF-IDF ở bước phân loại sau đó.  
3. **Nhạy cảm với nhiễu nền và góc chụp (Background Clutter & Viewpoint Variation):** Các mẫu có độ tinh khiết thấp như `{157, 191}` (47,3%) và sự chênh lệch số lượng mẫu của lớp `airplanes` so với `motorbikes` cho thấy SIFT cục bộ vẫn chịu ảnh hưởng khi nền ảnh phức tạp hoặc đối tượng thay đổi góc nhìn. Có thể cải thiện bằng cách tiền phân đoạn tiền cảnh hoặc thay thế RootSIFT bằng đặc trưng bản đồ kích hoạt (feature maps) từ mạng nơ-ron tích chập (CNN).  
4. **Chưa thực nghiệm quét định lượng đa giá trị k:** Nghiên cứu hiện cố định \$k \= 300\$; trong các bước mở rộng tiếp theo, cần khảo sát thêm \$k \\in {100, 300, 500}\$ để đo đạc trực tiếp đường cong biến thiên của độ tinh khiết trung bình và thời gian chạy CHARM theo \$k\$.

