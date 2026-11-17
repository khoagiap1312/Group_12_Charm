
# Check file có chuẩn SPMF ko
function check_spmf(path::String)

    # 1. KIỂM TRA ĐỊNH DẠNG FILE
    if !endswith(lowercase(path), ".txt")
        println("LỖI: File truyền vào không phải là file .txt!")
        println("File: $path")
        return false, false, false # Dừng hàm ngay lập tức
    end

    is_spmf_valid = true
    is_sorted = true
    has_duplicate = false
    
    # Khai báo Set MỘT LẦN duy nhất để tái sử dụng, giúp tốc độ cực nhanh và không tốn RAM
    seen_items = Set{Int}() 
    
    open(path, "r") do file
        for (line_idx, line) in enumerate(eachline(file))
            line = strip(line)
            
            if isempty(line) || startswith(line, "@") || startswith(line, "%")
                continue
            end
            
            tokens = split(line)
            prev_val = -1
            
            for token in tokens
                val = tryparse(Int, token)
                
                if val === nothing
                    println("Dòng $line_idx: [Lỗi Cú Pháp] '$token' không phải số nguyên.")
                    is_spmf_valid = false
                    break
                end
                
                # Gặp -1 (hết itemset) hoặc -2 (hết sequence)
                if val == -1 || val == -2
                    prev_val = -1 
                    empty!(seen_items) # Xóa sạch Set để dùng cho itemset tiếp theo
                    continue
                end
                
                if val <= 0
                    println("Dòng $line_idx: [Lỗi SPMF] Item <= 0 ($val).")
                    is_spmf_valid = false
                end
                
                # 1. KIỂM TRA DUPLICATE (BẰNG SET)
                if val in seen_items
                    println("Dòng $line_idx: [Lỗi Duplicate] Item '$val' bị lặp lại trong cùng itemset!")
                    has_duplicate = true
                    is_spmf_valid = false # Lặp lại thì chắc chắn vi phạm SPMF
                else
                    push!(seen_items, val)
                end
                
                # 2. KIỂM TRA SORT (TĂNG DẦN)
                if prev_val != -1 && val < prev_val
                    println("Dòng $line_idx: [Lỗi Sort] '$val' đứng sau '$prev_val'.")
                    is_sorted = false
                end
                
                prev_val = val
            end
            
            # Reset Set khi hết 1 dòng (dành cho file Transaction không có -1)
            empty!(seen_items)
        end
    end
    
    println("\n--- KẾT QUẢ KIỂM TRA ĐỘ CHÍNH XÁC ---")
    println("File: $path")
    println("- Định dạng (SPMF): ", is_spmf_valid ? "HỢP LỆ ✅" : "CÓ LỖI ❌")
    println("- Sắp xếp (Sort): ", is_sorted ? "ĐÃ SORT ✅" : "CHƯA SORT ❌")
    
    return is_spmf_valid, is_sorted, !has_duplicate
end

