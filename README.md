# Group 12 - CHARM (Closed Itemset Mining)

Cài đặt lại từ đầu thuật toán **CHARM** (Zaki & Hsiao, 2002) khai thác **tập đóng phổ biến**
(frequent closed itemsets) bằng **Julia**, so sánh với cài đặt tham chiếu `Charm_bitset` của
[SPMF](https://www.philippe-fournier-viger.com/spmf/).

Có hai bản cài đặt chạy trên cùng một thuật toán lõi (`src/algorithm/charm_core.jl`):

| Bản | Cách lưu tidset | File |
|---|---|---|
| `baseline` | mảng số nguyên đã sắp xếp (Tidset chuẩn) | `src/algorithm/baseline_solver.jl` |
| `optimized` | bitset (`BitVector`), phép giao bằng AND trên từng khối 64 bit | `src/algorithm/optimized_solver.jl` |

## Thành viên nhóm

| Vai trò | Họ tên | MSSV |
|---|---|---|
| Thành viên 1 - Core Algorithm & Baseline | Giáp Đăng Khoa | 24127186 |
| Thành viên 2 - Optimization & Benchmark | Nguyễn Hoàng Đăng Khoa | 24127187 |
| Thành viên 3 - Data Pipeline & Applications | Trần Ngọc Quân | 24127518 |

## Hướng dẫn chạy

Các lệnh dưới đây chạy trong thư mục gốc của repo, dùng được trên Windows (PowerShell), Linux và macOS.

### 1. Yêu cầu môi trường

| Phần mềm | Dùng để | Ghi chú |
|---|---|---|
| **Julia** | chạy toàn bộ code | CI dùng 1.10, nhóm phát triển trên 1.13. Tải tại <https://julialang.org/downloads/> |
| **Java** | chạy SPMF để đối chiếu và benchmark | không bắt buộc để chạy thuật toán và test. CI dùng JDK 17 |
| **Python** | chỉ cho các notebook tiền xử lý dữ liệu ứng dụng (`src/pre-processing/`) | thư viện ở `requirements.txt` |

### 2. Cài thư viện Julia

```bash
git clone https://github.com/khoagiap1312/Group_12_Charm.git
cd Group_12_Charm
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Lần đầu chạy lệnh này cần vài phút để tải và biên dịch thư viện. Bản thuật toán lõi chỉ dùng thư viện chuẩn
của Julia, các thư viện còn lại phục vụ tải dữ liệu và tiền xử lý.

### 3. Chạy thuật toán (CLI)

```bash
julia src/main.jl --input <file> --minsup <ngưỡng> [--output <file>] [--algo baseline|optimized]
```

| Tham số | Ý nghĩa | Mặc định |
|---|---|---|
| `-i, --input` | file giao dịch định dạng SPMF `.txt` (bắt buộc) | |
| `-m, --minsup` | ngưỡng support tối thiểu (bắt buộc), xem bảng dưới | |
| `-o, --output` | file kết quả | `output.txt` |
| `-a, --algo` | `baseline` hoặc `optimized` | `baseline` |
| `-r, --order` | thứ tự duyệt item: `none`, `support_asc`, `support_desc` (chỉ ảnh hưởng tốc độ) | `none` |
| `-w, --warmup` | `1` = biên dịch trước để thời gian đo không chứa JIT (dùng khi benchmark) | `0` |
| `-h, --help` | in hướng dẫn | |

`--minsup` nhận 3 dạng:

| Dạng | Ví dụ | Nghĩa |
|---|---|---|
| phần trăm (giống SPMF) | `40%`, `33.3%` | 40% số giao dịch, khoảng `(0%, 100%]` |
| phân số | `0.4` | 40% số giao dịch, khoảng `(0, 1]` |
| số tuyệt đối | `3` | tối thiểu 3 giao dịch, số nguyên `>= 1` |

Số giao dịch tối thiểu được tính bằng `ceil(minsup × số giao dịch)`, giống SPMF.

**Ví dụ** với CSDL nhỏ `data/toy/sample.txt` (6 giao dịch, mỗi dòng là một giao dịch, các item là số nguyên cách nhau bằng dấu cách):

```bash
julia src/main.jl -i data/toy/sample.txt -m 40% -a optimized -o result.txt
```

In ra màn hình:

```
[OptimizedCharmSolver] Transactions: 6 | MinSup Count: 3 | Closed Itemsets: 7 | Read: ... ms | Time: ... ms | Write: ... ms | Total: ... ms | PeakRSS: ... MB
```

| Trường | Ý nghĩa |
|---|---|
| `MinSup Count` | số giao dịch tối thiểu sau khi quy đổi từ `--minsup` |
| `Closed Itemsets` | số tập đóng phổ biến tìm được |
| `Read` / `Write` | thời gian đọc file vào / ghi kết quả ra |
| `Time` | thời gian riêng của thuật toán (`fit!`) |
| `Total` | `Read + Time + Write` |
| `PeakRSS` | RAM đỉnh của tiến trình |

File `result.txt` ghi mỗi tập đóng một dòng theo định dạng của SPMF: `<các item> #SUP: <support>`
(thứ tự các dòng có thể khác SPMF, nội dung giống nhau):

```
2 #SUP: 6
2 5 #SUP: 5
1 2 5 #SUP: 4
...
```

Sai tham số hoặc sai đường dẫn file thì chương trình in một dòng `Error: ...` và thoát với mã 1.

### 4. Chạy kiểm thử

```bash
julia --project=. tests/runtests.jl
```

Lệnh này chạy toàn bộ test (unit test, edge case, đối chiếu kết quả với SPMF trên 5 CSDL). Mọi test phải qua.
Test **không cần Java**: kết quả SPMF chuẩn đã lưu sẵn trong `tests/expected/`. Nếu có Java và đặt `spmf.jar` vào
`tests/spmf.jar` thì test tự chạy SPMF trực tiếp thay vì đọc file lưu sẵn.

CI (GitHub Actions, `.github/workflows/test.yml`) chạy lại các test này và một bước kiểm tra CLI sau mỗi lần push.

### 5. Cài SPMF và đối chiếu kết quả

Tải SPMF về `tools/spmf.jar` (file này nằm trong `.gitignore`, không được commit):

```bash
mkdir -p tools
curl -L -o tools/spmf.jar https://www.philippe-fournier-viger.com/spmf/spmf.jar
```

Chạy SPMF trực tiếp (minsup theo `%`):

```bash
java -jar tools/spmf.jar run Charm_bitset data/toy/sample.txt out.txt 40%
```

So kết quả của nhóm (baseline và optimized) với SPMF, từng tập đóng và support:

```bash
julia scripts/benchmark.jl compare data/toy/sample.txt 0.4
```

```
baseline  OK: 7 vs SPMF 7 | thiếu 0, thừa 0, sai support 0
optimized OK: 7 vs SPMF 7 | thiếu 0, thừa 0, sai support 0
```

`OK` nghĩa là khớp 100%. Nếu lệch, script báo số itemset thiếu, thừa và sai support.

### 6. Tải dữ liệu benchmark

Dữ liệu lớn không nằm trong repo (thư mục `data/` trừ `data/toy/` bị `.gitignore`), được lưu trên Hugging Face:
<https://huggingface.co/datasets/Quanbro7/Charm_Dataset>

```bash
julia --project=. scripts/load_dataset.jl
```

Script tải về `data/` (bỏ qua file đã có):

| Thư mục | Nội dung | Dung lượng |
|---|---|---|
| `data/benchmark/origin/` | 4 tập benchmark: `chess.txt`, `mushrooms.txt`, `retail.txt`, `T10I4D100K.txt`, và `accidents.txt` | khoảng 45 MB |
| `data/benchmark/scale/` | tập con 10/25/50/75/100% giao dịch (thực nghiệm scalability) | khoảng 116 MB |
| `data/benchmark/length/` | CSDL tổng hợp có độ dài giao dịch tăng dần | khoảng 14 MB |
| `data/application/` | dữ liệu đã tiền xử lý cho hai ứng dụng (Chương 3) | khoảng 19 MB |

Thêm `--raw true` để tải cả dữ liệu thô của ứng dụng log (rất nặng, khoảng 3,5 GB): `julia --project=. scripts/load_dataset.jl --raw true`.

### 7. Chạy benchmark

Cần Java và `tools/spmf.jar` (mục 5), và dữ liệu ở `data/benchmark/origin/` (mục 6).

```bash
julia scripts/benchmark.jl bench <dataset> <minsup...> [--repeat 3] [--timeout 120]
```

`<dataset>` là một trong `chess`, `mushroom`, `retail`, `t10i4d100k`. Các minsup là **phân số**. Các lệnh đã dùng để
sinh `results/`:

```bash
julia scripts/benchmark.jl bench chess      0.9 0.85 0.8 0.75 0.7 0.65 0.6
julia scripts/benchmark.jl bench mushroom   0.5 0.4 0.3 0.2 0.15 0.1
julia scripts/benchmark.jl bench retail     0.02 0.01 0.005 0.002 0.001 0.0005
julia scripts/benchmark.jl bench t10i4d100k 0.02 0.01 0.005 0.0025 0.001 0.0005
```

Với mỗi mức minsup, script chạy ba engine (`spmf`, `baseline`, `optimized`), mỗi cấu hình **3 lần**, mỗi lần là một tiến
trình riêng, lấy **trung vị**. Engine nào quá `--timeout` giây thì bỏ qua các minsup thấp hơn. Cả bốn lệnh mất khoảng 10 đến 15 phút.
Các thí nghiệm của giai đoạn 3 (cần thêm `matplotlib` để vẽ):

```bash
julia scripts/benchmark.jl correctness                    # khớp SPMF, results/correctness.csv
julia scripts/benchmark.jl scale retail 0.005 0.002       # tập con 10-100% giao dịch
julia scripts/benchmark.jl length 0.02 0.01               # CSDL tổng hợp T10-T40
julia scripts/benchmark.jl improve                        # thứ tự item tăng/giảm dần
julia scripts/analysis.jl                                 # kích thước tidset và Diffset
python scripts/plot_results.py                            # docs/figures/*, docs/tables_tv2.md
```

Báo cáo phần TV2 (Chương 1 mục bản tối ưu và Chương 2) nằm ở `docs/TV2_Chuong1_Chuong2.md`.

Benchmark không dùng yếu tố ngẫu nhiên nên chạy lại cho kết quả cùng hình dạng (thời gian dao động theo máy).

Kết quả ghi vào `results/`:

| File | Nội dung |
|---|---|
| `raw_<dataset>.csv` | từng lần chạy riêng lẻ |
| `summary_<dataset>.csv` | trung vị 3 lần, mỗi dòng ứng với một (minsup, engine) |

| Cột | Ý nghĩa |
|---|---|
| `dataset`, `minsup`, `engine` | tập dữ liệu, ngưỡng (phân số), engine |
| `run` | lần chạy thứ mấy (chỉ có trong `raw_*`) |
| `status` | `ok`, `timeout`, `error` hoặc `skipped` |
| `time_ms` | thời gian tổng, dùng để so với SPMF. Julia: đọc + chạy + ghi file (sau warm-up). SPMF: "Total time" do SPMF báo (không gồm khởi động JVM) |
| `fit_ms` | chỉ riêng thuật toán của Julia, dùng để so `baseline` với `optimized` (để trống với SPMF) |
| `wall_s` | thời gian cả tiến trình, gồm khởi động Julia hoặc JVM |
| `peak_mb` | RAM đỉnh. Julia: RSS của tiến trình (gồm khoảng 225 MB nền của runtime). SPMF: bộ nhớ heap do JVM báo, **không so trực tiếp với Julia** |
| `n_closed` | số tập đóng phổ biến tìm được |

## Cấu trúc thư mục

```
Group_12_Charm/
├── README.md
├── Project.toml, Manifest.toml      # môi trường Julia
├── requirements.txt                 # thư viện Python cho notebook tiền xử lý
├── src/
│   ├── main.jl                      # CLI
│   ├── interfaces.jl                # kiểu và hàm chung (AbstractTidset, AbstractCharmSolver, ...)
│   ├── io_utils.jl                  # đọc và ghi định dạng SPMF
│   ├── algorithm/
│   │   ├── charm_core.jl            # thuật toán CHARM (dùng chung cho hai bản)
│   │   ├── baseline_solver.jl       # tidset là mảng số nguyên
│   │   └── optimized_solver.jl      # tidset là bitset
│   ├── datagen.jl, utils.jl         # sinh dữ liệu, kiểm tra định dạng SPMF
│   └── pre-processing/              # notebook tiền xử lý dữ liệu cho hai ứng dụng
├── scripts/
│   ├── benchmark.jl                 # đối chiếu SPMF và benchmark
│   ├── analysis.jl, plot_results.py # phân tích tidset/Diffset, vẽ biểu đồ và bảng (TV2)
│   ├── bench_scale_length.jl        # benchmark scalability và độ dài giao dịch (TV3)
│   ├── analyze_caltech101.py, analyze_web_logs.py  # phân tích hai ứng dụng (TV3)
│   ├── load_dataset.jl              # tải dữ liệu từ Hugging Face
│   ├── generate_data.jl             # sinh tập con và dữ liệu tổng hợp
│   └── invert_parse.jl              # đổi kết quả từ mã số về tên item
├── tests/                           # unit test, test đối chiếu SPMF, tests/expected/
├── data/toy/                        # CSDL nhỏ để kiểm thử nhanh
├── results/                         # kết quả benchmark (CSV)
├── notebooks/demo.ipynb             # demo trên Google Colab
└── docs/                            # báo cáo: Chương 1-2 (TV2), Chương 3 (TV3), figures/, tables_tv2.md
```

## Output lần chạy test gần nhất

`julia --project=. tests/runtests.jl` (Julia 1.13.4):

```
Test Summary:                                         | Pass  Total  Time
Group 12 CHARM - Full Test Suite                      |  189    189  8.8s
  Unit test for baseline                              |   48     48  2.3s
  BitsetTidset & Optimized Solver                     |   34     34  1.0s
  Edge Cases & Corner Cases                           |   26     26  0.3s
  Group 12 CHARM - Automated Correctness Verification |   40     40  2.8s
  Item order: thứ tự duyệt item không đổi kết quả     |   41     41  1.4s
```

Đối chiếu với SPMF trên 5 CSDL (cả hai bản đều khớp 100%):

```
Dataset              | MinSup | Solver     | SPMF Cnt  | Ours Cnt  | Matched   | Match Rate
sample               | 2      | Baseline   | 9         | 9         | 9         |    100.00%
sample               | 2      | Optimized  | 9         | 9         | 9         |    100.00%
contextPasquier99    | 2      | Baseline   | 5         | 5         | 5         |    100.00%
contextPasquier99    | 2      | Optimized  | 5         | 5         | 5         |    100.00%
contextZart          | 2      | Baseline   | 7         | 7         | 7         |    100.00%
contextZart          | 2      | Optimized  | 7         | 7         | 7         |    100.00%
contextItemsetTree   | 2      | Baseline   | 6         | 6         | 6         |    100.00%
contextItemsetTree   | 2      | Optimized  | 6         | 6         | 6         |    100.00%
contextRelim         | 2      | Baseline   | 10        | 10        | 10        |    100.00%
contextRelim         | 2      | Optimized  | 10        | 10        | 10        |    100.00%
```

## Tài nguyên & Google Colab

- Dữ liệu benchmark và dữ liệu ứng dụng: <https://huggingface.co/datasets/Quanbro7/Charm_Dataset>
- Demo notebook trên Google Colab: ... (đang cập nhật)
  - Lưu ý phiên bản Julia: máy local và CI dùng Julia 1.13.4, còn Colab cài sẵn Julia 1.12.6. Notebook vẫn chạy đúng và cho cùng số tập đóng với bản local (đã đối chiếu ở các cấu hình trong notebook), nên không ghim lại phiên bản.
- Báo cáo: `docs/Report.pdf` (đang cập nhật)

## Tài liệu tham khảo chính

- M. J. Zaki and C.-J. Hsiao, "CHARM: An Efficient Algorithm for Closed Itemset Mining," *SIAM International Conference on Data Mining (SDM)*, 2002.
- P. Fournier-Viger et al., "The SPMF Open-Source Data Mining Library," <https://www.philippe-fournier-viger.com/spmf/>
