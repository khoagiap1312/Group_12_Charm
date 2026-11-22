# Phần của TV2: Chương 1 (mục Bản tối ưu) và Chương 2 (Thực nghiệm và đánh giá)

> Bản thảo để ghép vào `docs/Report.pdf` (mẫu IEEE). Các hình nằm ở `docs/figures/`, các bảng số liệu sinh tự động
> từ `results/*.csv` bằng `python scripts/plot_results.py` và nằm ở `docs/tables_tv2.md` (số liệu trong văn bản
> được lấy từ các bảng đó).

---

# CHƯƠNG 1 (mục 1.x). Bản cài đặt tối ưu bằng bitset

## 1.1 Động lực

Trong CHARM, mỗi nút của IT-tree (itemset–tidset tree) gắn với một itemset $X$ và tập định danh giao dịch
(*tidset*) $t(X)\subseteq T=\{1,\dots,n\}$ chứa các giao dịch có chứa $X$; support của $X$ là $\sigma(X)=|t(X)|$.
Với mỗi cặp nút anh em $(X_i,X_j)$, thuật toán phải thực hiện bốn thao tác trên tidset: (i) giao
$t(X_i\cup X_j)=t(X_i)\cap t(X_j)$ kèm đếm support, (ii) kiểm tra bằng nhau $t(X_i)=t(X_j)$ (tính chất 1),
(iii) kiểm tra tập con $t(X_i)\subseteq t(X_j)$ (tính chất 2 và 3), (iv) băm tidset để tra bảng kiểm tra
subsumption. Nghĩa là toàn bộ chi phí thuật toán nằm ở các phép toán tập hợp trên tidset, nên cách biểu diễn tidset
quyết định hiệu năng. Bản `baseline` (do TV1 cài) lưu tidset dạng mảng số nguyên đã sắp xếp. Bản `optimized`
thay biểu diễn này bằng **bitset** và giữ nguyên toàn bộ phần còn lại của thuật toán.

## 1.2 Biểu diễn bitset

Đặt $w=\lceil n/64\rceil$. Tidset $t(X)$ được biểu diễn bằng vector bit $B_X\in\{0,1\}^n$ với $B_X[k]=1$ khi và
chỉ khi giao dịch $k$ chứa $X$, lưu trong $w$ từ 64 bit. Các phép toán chuyển thành phép toán bit theo từng từ:

| Thao tác | Baseline (mảng đã sắp xếp) | Optimized (bitset) |
|---|---|---|
| Giao $t(X)\cap t(Y)$ | duyệt merge hai mảng | $B_X\ \mathrm{AND}\ B_Y$ trên từng từ |
| Support $\sigma(X)$ | độ dài mảng | $\sum_k \mathrm{popcount}(B_X[k])$, tính cùng lượt với phép giao rồi lưu sẵn |
| Bằng nhau | so sánh hai mảng | so sánh từng từ |
| Tập con $t(X)\subseteq t(Y)$ | duyệt hai con trỏ | $B_X\ \mathrm{AND}\ (\mathrm{NOT}\ B_Y)=0$ |
| Băm | tổng các tid (như bài báo gốc) | băm mảng các từ 64 bit |

Hai điểm cần lưu ý khi cài đặt:

- Support được tính ngay trong lượt duyệt của phép giao và lưu cùng bitset, nên `length` của tidset là $O(1)$.
  Nếu không lưu sẵn, mỗi lần cần support phải đếm lại $w$ từ.
- Hàm băm và phép so sánh dựa vào các từ thô của bitset. Điều này đúng vì `BitVector` của Julia luôn giữ các bit
  thừa ở từ cuối bằng 0, nên hai tidset bằng nhau luôn có cùng mảng từ.

## 1.3 Cài đặt

Bản tối ưu nằm ở `src/algorithm/optimized_solver.jl` (khoảng 60 dòng), chỉ định nghĩa kiểu `BitsetTidset` và các
phương thức của giao diện chung (`tid_intersect`, `tid_issubset`, `tid_hash`, `create_tidset`). Thuật toán lõi
`charm_core.jl` được dùng chung cho cả hai bản, nên hai bản **chỉ khác nhau ở biểu diễn tidset**. Điều này bảo đảm
mọi chênh lệch về thời gian và bộ nhớ ở Chương 2 là do biểu diễn tidset gây ra.

```
Thuật toán 1. tid_intersect(A, B)               Thuật toán 2. tid_issubset(A, B)
 1: R ← bitset mới độ rộng n                      1: nếu cnt(A) > cnt(B) thì trả về false
 2: c ← 0                                         2: với mỗi khối 8 từ k..k+7:
 3: với mỗi từ k = 1..w:                          3:    acc ← OR của (A[j] AND NOT B[j]) trên khối
 4:    R[k] ← A[k] AND B[k]                       4:    nếu acc ≠ 0 thì trả về false
 5:    c ← c + popcount(R[k])                     5: trả về true
 6: trả về (R, support = c)
```

- Vòng lặp của `tid_intersect` được đánh dấu `@inbounds @simd` để trình biên dịch vector hóa AND và popcount.
- `tid_issubset` cần thoát sớm khi tìm thấy một từ vi phạm, mà `@simd` không cho phép thoát sớm giữa vòng. Vì vậy
  hàm duyệt theo khối 8 từ: vector hóa trong khối và kiểm tra thoát sớm giữa các khối.
- Mỗi phép giao cấp phát một bitset mới, vì tidset của nút con phải tồn tại độc lập với nút cha trong suốt quá trình
  duyệt đệ quy.
- Khi đo, chương trình có tùy chọn `--warmup 1`: biên dịch trước (đọc, `fit!`, ghi) trên vài giao dịch để thời gian đo
  không chứa thời gian biên dịch JIT của Julia.

Về `@simd`: chúng tôi áp dụng theo yêu cầu của đề, nhưng so sánh trước và sau cho thấy chênh lệch nằm trong
khoảng nhiễu của các lần đo (cùng một đoạn mã baseline chưa đổi cũng chậm hơn 20% đến 36% giữa hai lượt chạy
cách nhau vài giờ). Vì vậy chúng tôi **không** tuyên bố cải thiện nào đến từ `@simd`.

## 1.4 Phân tích độ phức tạp

Ký hiệu: $n$ là số giao dịch, $w=\lceil n/64\rceil$, $\sigma$ là kích thước của tidset, $N_\cap$ là số phép giao
mà thuật toán thực hiện. Vì hai bản dùng chung thuật toán lõi nên $N_\cap$ như nhau; khác biệt chỉ là chi phí mỗi
phép giao và kích thước mỗi tidset.

**Thời gian mỗi phép giao.**

- Baseline: $\Theta(\sigma(X)+\sigma(Y))$ bước merge. Mỗi bước có một phép so sánh và một nhánh khó dự đoán.
- Optimized: $\Theta(w)=\Theta(n/64)$ phép AND kèm popcount, **không phụ thuộc** $\sigma$, và vector hóa được.

Gọi $c_e$ là chi phí một bước merge và $c_w$ là chi phí xử lý một từ 64 bit ($c_w<c_e$ vì phép AND không có nhánh và
chạy SIMD). Tổng thời gian của hai bản xấp xỉ

$$T_{\text{base}}\approx c_e\sum_{\cap}\big(\sigma_a+\sigma_b\big),\qquad T_{\text{bit}}\approx c_w\,w\,N_\cap .$$

Bitset nhanh hơn khi trung bình $\bar\sigma_a+\bar\sigma_b$ của các phép giao lớn hơn $(c_w/c_e)\,w$. Nói cách khác,
**bitset có lợi khi các tidset được giao đủ "đặc" so với bề rộng $n$ của bitset**, bất kể thuật toán khai thác sinh ra
bao nhiêu nút.

**Bộ nhớ mỗi tidset.** Baseline lưu mỗi tid bằng số nguyên 64 bit: $8\sigma$ byte. Bitset lưu $8w\approx n/8$ byte
bất kể $\sigma$. Bitset gọn hơn khi $8\sigma>n/8$, tức $\sigma/n>1/64\approx 1{,}6\%$.

**Hệ quả cho hai loại dữ liệu.**

- *Dữ liệu dày* (Chess, Mushroom): support của hầu hết item rất cao (Chess có độ dày 49%), tidset ở mọi độ sâu đều
  chiếm một phần lớn của $n$. Các tidset vượt xa ngưỡng $1/64$, nên bitset vừa nhanh hơn vừa không tốn thêm bộ nhớ.
- *Dữ liệu thưa* (Retail, T10I4D100K): support trung bình của một item rất nhỏ (Retail: độ dày 0,1%), và tidset ở
  các nút sâu của IT-tree còn nhỏ hơn nữa vì mỗi bước giao chỉ làm giảm support. Khi hạ minsup, số nút sâu tăng
  mạnh và phần lớn phép giao có $\sigma_a+\sigma_b\ll w$, nên bitset phải quét $w$ từ gần như toàn số 0. Phần 2.8
  đo trực tiếp tỉ lệ này.

## 1.5 Kiểm chứng tính đúng và tính tương thích

Bản `optimized` cài đặt đúng giao diện của baseline (`AbstractTidset`, `AbstractCharmSolver`) nên chạy chung toàn
bộ bộ kiểm thử tự động: `julia --project=. tests/runtests.jl` gồm 189 kiểm thử, tất cả đều qua. Trong đó có kiểm thử
đối chiếu baseline với optimized trên cùng dữ liệu, kiểm thử các thao tác trên `BitsetTidset`, các trường hợp biên
(CSDL rỗng, một giao dịch, minsup bằng 100%, item chưa sắp xếp) và đối chiếu với kết quả SPMF. Kết quả đối chiếu
trên các tập benchmark ở Chương 2 (mục 2.2).

## 1.6 So sánh trước và sau tối ưu

Thời gian thuật toán `fit!` (trung vị 3 lần, đã loại JIT) và RAM đỉnh; số liệu đầy đủ ở bảng B2 (`docs/tables_tv2.md`).

| Dataset (minsup) | Baseline (ms) | Optimized (ms) | Tăng tốc | RAM Base → Opt (MB) |
|---|---|---|---|---|
| Chess (0,8) | 173,1 | 4,0 | 43,8× | 228 → 225 |
| Chess (0,6) | 2498,4 | 150,7 | 16,6× | 277 → 259 |
| Mushroom (0,15) | 184,9 | 8,0 | 23,0× | 233 → 225 |
| Mushroom (0,1) | 262,5 | 21,5 | 12,2× | 235 → 225 |
| T10I4D100K (0,02) | 663,5 | 152,8 | 4,3× | 278 → 284 |
| T10I4D100K (0,0005) | 7026,6 | 7196,6 | 1,0× | 335 → 358 |
| Retail (0,02) | 99,4 | 59,6 | 1,7× | 265 → 264 |
| Retail (0,0005) | 16345,5 | 27407,0 | 0,6× | 288 → 387 |

Trên dữ liệu dày, bitset nhanh hơn 9 đến 44 lần (Chess) và 1,1 đến 23 lần (Mushroom). Trên dữ liệu thưa, lợi thế
giảm dần khi hạ minsup và đảo chiều ở Retail (minsup ≤ 0,001) và hòa ở T10I4D100K (minsup 0,0005). RAM đỉnh của
Julia có nền khoảng 225 MB của runtime, nên chênh lệch chỉ đáng kể ở các ca thưa, minsup thấp (Retail 0,0005: tăng
99 MB). Kết quả khớp phân tích ở mục 1.4.

---

# CHƯƠNG 2. Thực nghiệm và đánh giá

## 2.1 Thiết lập

- **Máy**: Intel Core i7-1360P (12 nhân, 16 luồng), RAM 15,6 GB, Windows 11; Julia 1.13.4; Java 25.0.1 (SPMF).
- **Phương pháp đo**: mỗi lần chạy là một tiến trình riêng; Julia chạy `--warmup 1` để loại thời gian JIT; lấy trung vị
  của 3 lần; hết 120 giây thì dừng và bỏ qua các lần sau của cùng cấu hình. `Thời gian tổng` của Julia gồm đọc, khai
  thác và ghi; của SPMF là "Total time" do SPMF báo (không gồm thời gian khởi động JVM). `fit_ms` chỉ tính thuật toán.
- **Dữ liệu** (bảng B1): Chess và Mushroom là dữ liệu dày (độ dày 49,3% và 19,3%); Retail và T10I4D100K là dữ liệu
  thưa (0,1% và 1,2%). Độ dày là độ dài giao dịch trung bình chia cho số item.
- **Đối chiếu**: SPMF `Charm_bitset` là cài đặt tham chiếu, các thí nghiệm đều chạy trên cùng tệp đầu vào.

## 2.2 Tính đúng (Hình 1, bảng B4)

Trên 13 cấu hình (4 tập, nhiều minsup), cả bốn biến thể (baseline, optimized, và hai biến thể sắp item tăng dần) đều
khớp 100% số tập đóng và support với SPMF. Tỉ lệ khớp tính bằng số itemset khớp hoàn toàn trên hợp hai tập kết quả.

## 2.3 Thời gian theo minsup, so với SPMF (Hình 2, 2b; bảng B2, B3)

Trục thời gian dùng thang log, minsup giảm dần về phía phải.

- **Chess và Mushroom (dày)**: Optimized nhanh hơn SPMF ở mọi minsup, từ 1,9 đến 3,8 lần (Chess) và 1,2 đến 2,2 lần
  (Mushroom). Baseline chậm hơn SPMF ở Chess khi minsup ≤ 0,85 (0,45 đến 0,83 lần) và ngang ở Mushroom.
- **Retail (thưa)**: Optimized nhanh hơn SPMF khi minsup ≥ 0,005 (1,4 đến 2,8 lần) nhưng chậm dần: 0,30 lần ở 0,002,
  0,12 lần ở 0,001 và 0,05 lần ở 0,0005 (27,6 s so với 1,4 s).
- **T10I4D100K (thưa)**: Optimized chậm hơn SPMF ở mọi minsup (0,12 đến 0,32 lần), tuy vẫn nhanh hơn baseline 2 đến
  4,3 lần trừ minsup 0,0005.

## 2.4 Số tập đóng (Hình 3)

Số tập đóng tăng nhanh khi hạ minsup (Chess: 498 → 98.392 từ minsup 0,9 xuống 0,6; Retail: 55 → 19.114 từ 0,02 xuống
0,0005). Số này giống nhau ở cả ba chương trình (mục 2.2), nên đường cong chỉ mô tả dữ liệu, không phải thuật toán.
Chi phí thực tế tăng theo số nút IT-tree được duyệt, thường lớn hơn nhiều số tập đóng.

## 2.5 RAM đỉnh (Hình 4)

Julia đo RSS của tiến trình (nền khoảng 225 MB), SPMF đo heap JVM, nên hai đại lượng **không so sánh trực tiếp**
được. Chỉ so baseline với optimized: ở dữ liệu dày, optimized bằng hoặc thấp hơn (Chess 0,6: 259 so với 277 MB); ở dữ
liệu thưa minsup thấp, optimized cao hơn (Retail 0,0005: 387 so với 288 MB), đúng với ngưỡng σ/n > 1/64 ở mục 1.4.

## 2.6 Khả năng mở rộng theo số giao dịch (Hình 5, bảng B5)

Chọn tập con 10, 25, 50, 75, 100% giao dịch của Retail, minsup tương đối cố định. Ở minsup 0,002, từ 10% lên 100%
dữ liệu, baseline tăng 6,2 lần (381 → 2371 ms), optimized tăng 14 lần (176 → 2491 ms), SPMF chỉ tăng 2,2 lần (368 →
812 ms). Optimized mở rộng kém hơn baseline là hợp lý: $w=n/64$ tăng tuyến tính theo $n$ trong khi tidset thưa không
tăng tương ứng. Ở minsup 0,005, ba chương trình đều dưới 1 s nên chênh lệch nằm trong nhiễu. Chỉ đo trên Retail.

## 2.7 Ảnh hưởng độ dài giao dịch (Hình 6, bảng B6)

CSDL tổng hợp T10 đến T40 (20.000 giao dịch). Giao dịch dài làm số tập đóng tăng mạnh (minsup 0,01: 565 → 60.873).
Optimized nhanh hơn baseline từ 2 đến 10 lần (minsup 0,01, T25: 224 so với 2006 ms) và tăng đều hơn. SPMF nhanh
hơn optimized ở hầu hết cấu hình (ví dụ T30, minsup 0,01: 391 so với 549 ms); ngoại lệ là T25, minsup 0,01 (224 so với 268 ms).

## 2.8 Phân tích theo độ phức tạp: dữ liệu dày và dữ liệu thưa (Hình 8a, bảng B8)

Mục 1.4 dự đoán bitset có lợi khi $\bar\sigma_a+\bar\sigma_b > (c_w/c_e)\,w$. Chúng tôi đo trực tiếp bằng cách đếm kích
thước các tidset thực sự được giao khi chạy baseline (`scripts/analysis.jl`), so với $w=n/64$.

| Dataset (minsup) | $w$ | $\bar\sigma_a+\bar\sigma_b$ | Tỉ số với $w$ | % phép giao có $\sigma_a+\sigma_b<w$ |
|---|---|---|---|---|
| Chess (0,7) | 50 | 5006 | 100 | 0% |
| Mushroom (0,2) | 132 | 5668 | 43 | 0% |
| Retail (0,005) | 1378 | 2984 | 2,2 | 40% |
| Retail (0,001) | 1378 | 629 | 0,46 | 96% |
| T10I4D100K (0,005) | 1563 | 3286 | 2,1 | 9% |
| T10I4D100K (0,001) | 1563 | 1774 | 1,1 | 56% |

Ở dữ liệu dày, tidset lớn hơn bề rộng bitset 43 đến 100 lần và không phép giao nào nhỏ hơn $w$, nên bitset thắng
lớn (tới 44×). Ở Retail minsup 0,001, 96% phép giao có tổng kích thước nhỏ hơn $w$: bitset quét 1378 từ gần như
toàn số 0 trong khi merge mảng chỉ cần vài trăm bước, đúng với kết quả bitset chậm hơn baseline (0,9× rồi 0,6×).
Bảng cũng cho thấy tỉ số quanh 1 đến 2 vẫn cho bitset thắng ở T10I4D100K (2,0 đến 3,3×), nên hệ số $c_w/c_e$ thực tế
nhỏ hơn 1, tức mỗi từ 64 bit rẻ hơn mỗi bước merge vài lần, và điểm hòa nằm ở tỉ số khoảng 0,5 đến 1.

## 2.9 So với SPMF: nguyên nhân (giả thuyết)

Dưới đây là các giả thuyết, **chưa được kiểm chứng riêng**:

- SPMF nhanh hơn rõ ở dữ liệu thưa, nơi số nút lớn và mỗi phép giao rất nhỏ. Với dữ liệu này, hằng số mỗi nút (cấp phát
  bitset đủ rộng $n/64$ từ cho từng nút con, băm toàn bộ mảng từ) của bản Julia có thể lớn hơn của SPMF.
- Ở dữ liệu dày, chi phí phép giao chiếm ưu thế nên lợi thế vector hóa của bitset Julia lộ ra.
- Thời gian SPMF không gồm khởi động JVM, trong khi thời gian Julia gồm đọc và ghi tệp; điều này làm lệch nhẹ ở các ca
  chạy dưới 1 giây.

## 2.10 Điểm mạnh và điểm yếu

- **Mạnh**: kết quả đúng tuyệt đối so với SPMF; nhanh hơn baseline 9 đến 44 lần trên Chess; nhanh hơn SPMF trên
  dữ liệu dày; mã ngắn (khoảng 60 dòng), dùng chung thuật toán lõi với baseline nên kết quả so sánh sạch.
- **Yếu**: trên dữ liệu thưa với minsup thấp, bitset tốn thời gian quét các từ rỗng và tốn RAM hơn, thậm chí chậm hơn baseline
  (Retail 0,0005); chậm hơn SPMF vài đến hàng chục lần ở T10I4D100K và Retail.

## 2.11 Hai hướng cải tiến tiếp theo

### 2.11.1 Sắp xếp item theo support tăng dần (đã cài và đo; Hình 7, bảng B7)

*Cơ sở.* Thứ tự item chỉ ảnh hưởng tốc độ, không ảnh hưởng kết quả (đã kiểm thử trên 5 CSDL nhỏ và 13 cấu hình đối
chiếu SPMF). Nếu xử lý item có support nhỏ trước, các lớp tương đương ở cây con có tidset nhỏ và giao với nhiều anh em,
nên tổng $\sum(\sigma_a+\sigma_b)$ giảm theo bất đẳng thức hoán vị (ghép số lớn với số nhỏ cho tổng tích nhỏ nhất); các
tính chất 2 và 3 của CHARM cũng gộp được nhiều nút hơn sớm hơn. Đây là lập luận định tính về cận chi phí, không phải
chứng minh chặt về thời gian chạy.

*Kết quả.* Trên dữ liệu dày, tăng dần có lợi và giảm dần có hại: Chess 0,7 baseline 634 → 423 ms (tăng dần) và 1448 ms
(giảm dần); Chess 0,6 là 2072 → 1779 và 6284 ms; Mushroom 0,1: 189 → 152 ms. Với optimized: Chess 0,7 là 20 → 14 ms và
37 ms (giảm dần). Trên dữ liệu thưa **không có lợi ổn định**: Retail 0,005 baseline chậm đi (384 → 559 ms), Retail 0,001
optimized chậm đi (14958 → 19731 ms). Kết luận: chỉ nên bật `--order support_asc` cho dữ liệu dày; khi dữ liệu thưa
phải đo lại.

### 2.11.2 Diffset (dCHARM) (chỉ đo, chưa cài; Hình 8b, bảng B9)

*Cơ sở* (Zaki và Gouda, 2003). Với lớp tương đương tiền tố $P$, diffset $d(PX)=t(P)\setminus t(PX)$, và
$d(PXY)=d(PY)\setminus d(PX)$, $\sigma(PXY)=\sigma(PX)-|d(PXY)|$. Với hai item: $|d(XY)|=\sigma(X)-\sigma(XY)$, nên
$|d(XY)|<|t(XY)|$ khi và chỉ khi $\sigma(XY)>\sigma(X)/2$. Vậy Diffset nhỏ hơn Tidset khi item thường xuất hiện cùng nhau,
tức dữ liệu dày.

*Số đo.* Chess 0,7: 100% cặp có Diffset nhỏ hơn, kích thước trung bình 89 so với 2679 (nhỏ hơn 30 lần). Mushroom 0,2:
96% cặp, 617 so với 2834. Retail 0,005: 84% cặp nhưng mức lợi nhỏ (1036 so với 1161); Retail 0,001: 70% cặp.
T10I4D100K: chỉ 17% và 9% cặp, và Diffset **lớn hơn** Tidset (1654 so với 646). Kết luận: Diffset phù hợp Chess và
Mushroom, không phù hợp T10I4D100K.

*Lưu ý.* Với bitset độ rộng cố định, Diffset không giảm bộ nhớ; nó chỉ có ích khi lưu dưới dạng mảng thưa. Ở Chess,
bitset đã chỉ cần 50 từ mỗi phép giao, gần bằng 89 phần tử của Diffset, nên mức lợi so với *bitset* hẹp hơn mức lợi so với
mảng tidset. Ước lượng này chưa được đo bằng cài đặt thật.

## 2.12 Hạn chế

- Tệp `mushrooms.txt` có 8416 dòng (8124 dòng khác nhau) thay vì 8124 giao dịch chuẩn; nếu đổi tệp thì phải chạy lại
  các kết quả Mushroom.
- Nhiễu giữa các lần đo khoảng 20% đến 36% (cùng mã nguồn chạy cách nhau vài giờ); các chênh lệch dưới mức đó không có ý nghĩa.
  Vì vậy chúng tôi không tuyên bố lợi ích của `@simd`.
- Số liệu đo trên một máy, một hệ điều hành; scalability chỉ đo trên Retail; RAM của Julia và SPMF không so sánh được.

## Tài liệu tham khảo

1. M. J. Zaki, C.-J. Hsiao, "CHARM: An Efficient Algorithm for Closed Itemset Mining," *SDM*, 2002.
2. M. J. Zaki, K. Gouda, "Fast Vertical Mining Using Diffsets," *KDD*, 2003.
3. N. Pasquier, Y. Bastide, R. Taouil, L. Lakhal, "Discovering Frequent Closed Itemsets for Association Rules," *ICDT*, 1999.
4. P. Fournier-Viger et al., "The SPMF Open-Source Data Mining Library," *JMLR*, 2016.

## Phụ lục. Tái lập kết quả

```
julia --project=. scripts/benchmark.jl correctness
julia --project=. scripts/benchmark.jl bench <chess|mushroom|retail|t10i4d100k> <minsup...>
julia --project=. scripts/benchmark.jl scale retail 0.005 0.002
julia --project=. scripts/benchmark.jl length 0.02 0.01
julia --project=. scripts/benchmark.jl improve
julia --project=. scripts/analysis.jl
python scripts/plot_results.py        # cần matplotlib; sinh docs/figures/* và docs/tables_tv2.md
```
