#=  
- Chạy julia ./scripts/load_dataset.jl để load dataset trên huggingface về
=#
using HuggingFaceApi
using Downloads

repo_id = "Quanbro7/Charm_Dataset"
local_dir = "data/benchmark"

info = HuggingFaceApi.dataset_info(repo_id)

for sibling in info.siblings
    file_path = sibling.rfilename

    if startswith(file_path, "length/") || startswith(file_path, "origin/") || startswith(file_path, "scale/")

        dest_path = joinpath(local_dir, file_path)
        folder_path = dirname(dest_path)
        mkpath(folder_path)

        url = "https://huggingface.co/datasets/$repo_id/resolve/main/$file_path"
        
        println("Đang tải: $file_path ...")
        # Gọi hàm download
        Downloads.download(url, dest_path)
    end

end

print("DONE")