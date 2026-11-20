using Pkg

Pkg.activate(@__DIR__)

using CSV
using DataFrames
using ArgParse

function decode_spmf_to_file(spmf_path::String, map_path::String, output_path::String)
    df_map = CSV.read(map_path, DataFrame, types=String)

    id_to_item = Dict{String, String}()

    for row in eachrow(df_map)
        id_to_item[row[1]] = row[2]
    end

    open(spmf_path, "r") do file_in
        open(output_path, "w") do file_out
            
            for line in eachline(file_in)
                line = strip(line)
                if isempty(line)
                    continue
                end

                if occursin("#SUP:", line)
                    parts = split(line, "#SUP:")
                    item_part = strip(parts[1])
                    sup_part = strip(parts[2])

                    decoded_items = [get(id_to_item, i, i) for i in split(item_part)]
                    write(file_out, join(decoded_items, " ") * " #SUP: " * sup_part * "\n")
                else
                    # Trường hợp không có #SUP:
                    decoded_items = [get(id_to_item, i, i) for i in split(line)]
                    write(file_out, join(decoded_items, " ") * "\n")
                end
            
            end
        
        end
    
    end
end

function decode_spmf_to_df(spmf_path::String, map_path::String)
    df_map = CSV.read(map_path, DataFrame, types=String)

    id_to_item = Dict{String, String}()

    for row in eachrow(df_map)
        id_to_item[row[1]] = row[2]
    end

    col_itemset = Vector{String}[]
    col_itemset_str = String[]
    col_length = Int[]
    col_support = Int[]

    for line in eachline(spmf_path)
        line = strip(line)
        if isempty(line) || !occursin("#SUP:", line)
            continue
        end

        parts = split(line, "#SUP:")
        items_part = strip(parts[1])
        sup_part = strip(parts[2])

        decoded_items = [get(id_to_item, i, i) for i in split(items_part)]

        support = parse(Int, sup_part)

        push!(col_itemset, decoded_items)
        push!(col_itemset_str, join(decoded_items, ", "))
        push!(col_length, length(decoded_items))
        push!(col_support, support)
    end

    return DataFrame(
        Itemset = col_itemset,
        Itemset_Str = col_itemset_str,
        Length = col_length,
        Support = col_support
    )
end

function main()
    # Cấu hình Argument Parser
    s = ArgParseSettings(description=".")

    @add_arg_table! s begin
        "--spmf"
            help = "Đường dẫn tới file SPMF (.txt)"
            required = true
        "--map"
            help = "Đường dẫn tới file từ điển mapping (.csv)"
            required = true
        "--output"
            help = "Đường dẫn tới file đầu ra. Không có, sẽ đọc thành DataFrame và in ra màn hình."
            default = ""
    end

    parsed_args = parse_args(ARGS, s)
    
    spmf_path = parsed_args["spmf"]
    map_path = parsed_args["map"]
    out_path = parsed_args["output"]

    if isempty(out_path)
        println("Không có cờ --output. Trích xuất dưới dạng DataFrame:\n")
        df = decode_spmf_to_df(spmf_path, map_path)
        println(df)
    else
        println("Đang xử lý và ghi file...")
        decode_spmf_to_file(spmf_path, map_path, out_path)
        println("DONE! File output tại: ", out_path)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end