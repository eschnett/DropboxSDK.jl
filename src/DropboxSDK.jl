module DropboxSDK

using ConfParser
using HTTP
using JSON



struct Authorization
    access_token::String
end

function read_authorization()::Authorization
    conf = ConfParse("secrets.http")
    parse_conf!(conf)
    access_token = retrieve(conf, "access_token")
    Authorization(access_token)
end



function files_list_folder(auth::Authorization, path::String)::
    Union{Nothing, Vector{String}}
    args = Dict("path" => path,
                "recursive" => false,
                "include_media_info" => false,
                "include_deleted" => false,
                "include_has_explicit_shared_members" => false,
                "include_mounted_folders" => true,
                )
    resp = HTTP.request("POST",
                        "https://api.dropboxapi.com/2/files/list_folder",
                        ["Authorization" => "Bearer $(auth.access_token)",
                         "Content-Type" => "application/json",
                         ],
                        JSON.json(args);
                        verbose=0)
    if ! (200 <= resp.status <= 299)
        println("Error:")
        println("Status: $(resp.status)")
        println(String(resp.body))
        return nothing
    end
    res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
    @assert !res["has_more"]
    res["entries"]
end



function main()
    auth = read_authorization()
    files = files_list_folder(auth, "")
    @show files
end

end
