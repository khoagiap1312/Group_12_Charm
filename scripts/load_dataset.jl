using HuggingFaceApi
using Downloads

repo_id = "Quanbro7/Charm_Dataset"
local_dir = normpath(joinpath(@__DIR__, "..", "data"))

function parse_args(args)
    raw_idx = findfirst(==("--raw"), args)
    isnothing(raw_idx) && return false
    raw_idx == length(args) && error("Missing value for --raw")

    value = lowercase(args[raw_idx + 1])
    value in ("true", "false") || error("--raw must be true or false")
    return value == "true"
end

raw = parse_args(ARGS)
info = HuggingFaceApi.dataset_info(repo_id)

for sibling in info.siblings
    file_path = sibling.rfilename

    if startswith(file_path, "benchmark/")
        dest_path = joinpath(local_dir, file_path)
    elseif startswith(file_path, "application/")
        !raw && !occursin("/pre_process/", file_path) && continue
        dest_path = joinpath(local_dir, file_path)
    else
        continue
    end

    if isfile(dest_path)
        println("Đã tồn tại, bỏ qua: $file_path")
        continue
    end

    mkpath(dirname(dest_path))
    url = "https://huggingface.co/datasets/$repo_id/resolve/main/$file_path"
    tmp_path = dest_path * ".part"

    println("Đang tải: $file_path ...")
    Downloads.download(url, tmp_path)
    mv(tmp_path, dest_path; force=true)
end

println("DONE")