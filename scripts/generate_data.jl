include(joinpath(@__DIR__, "..", "src", "datagen.jl"))


const BENCHMARK_DIR = "data/benchmark/origin"
const SCALE_OUT_DIR = joinpath(BENCHMARK_DIR, "..", "scale")
const LENGTH_OUT_DIR = joinpath(BENCHMARK_DIR, "..", "length")

# Tạo dữ liệu Scalability (10%, 25%, 50%, 75%, 100%) cho từng file .txt trong data/benchmark
println("--- TẠO TẬP DỮ LIỆU SCALABILITY ---")
for file in filter(f -> endswith(f, ".txt"), readdir(BENCHMARK_DIR; join=true))
    println(" -> Đang xử lý file gốc: $file")
    for pct in (10, 25, 50, 75, 100)
        out_path, n_lines = generate_scalability_subset(
            file, pct, RandomSampling(0);
            out_root = SCALE_OUT_DIR
        )
        println("    [+] Scale $(lpad(pct, 3))% -> $out_path ($n_lines giao dịch)")
    end
end

# Tạo dữ liệu Synthetic Transaction Length (Đặt NGOÀI vòng lặp file, chỉ chạy 1 lần)
println("\n--- TẠO DỮ LIỆU TỔNG HỢP THEO ĐỘ DÀI T ---")

for T in (10, 15, 20, 25, 30, 35, 40)
    out_path, n_lines = generate_synthetic_length_dataset(
        T, CFG;
        out_root = LENGTH_OUT_DIR
    )
    println("  [+] Length T=$T -> $out_path ($n_lines giao dịch)")
end