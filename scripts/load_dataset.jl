#=
- Mặc định: julia ./scripts/load_dataset.jl
- Tải raw: julia ./scripts/load_dataset.jl --raw true
- Không tải raw: julia ./scripts/load_dataset.jl --raw false
=#

using HuggingFaceApi
using Downloads

repo_id = "Quanbro7/Charm_Dataset"
local_dir = "data"

info = HuggingFaceApi.dataset_info(repo_id)

function parse_args(args)
    raw_idx = findfirst(==("--raw"), args)

    isnothing(raw_idx) && return false

    raw_idx == length(args) && error("Missing value for --raw")

    value = lowercase(args[raw_idx + 1])

    value in ("true", "false") ||
        error("--raw must be true or false")

    return value == "true"
end

raw = parse_args(ARGS)

for sibling in info.siblings
    file_path = sibling.rfilename

    if startswith(file_path, "length/") || startswith(file_path, "origin/") || startswith(file_path, "scale/")
        dest_path = joinpath(local_dir, "benchmark", file_path)        
    elseif startswith(file_path, "application/")
        if !raw && !occursin("pre_process/", file_path)
            continue
        end
        dest_path = joinpath(local_dir, file_path)      
    else
        continue
    end

    folder_path = dirname(dest_path)
    mkpath(folder_path)

    url = "https://huggingface.co/datasets/$repo_id/resolve/main/$file_path"
    
    println("Đang tải: $file_path ...")
    
    if isfile(dest_path)
        println("Đã tồn tại, bỏ qua: $file_path")
        continue
    end
    # Gọi hàm download
    Downloads.download(url, dest_path)

end

print("DONE")