module DropboxSDK

using ConfParser
using HTTP
using JSON



function mapget(fun::Function, dict::Dict, key, def=nothing)
    value = get(dict, key, nothing)
    if value === nothing return def end
    fun(value)
end



struct Error
    dict::Dict{String, Any}
end



struct Authorization
    access_token::String
end

function read_authorization()::Authorization
    access_token = nothing
    if access_token === nothing
        access_token = get(ENV, "DROPBOXSDK_ACCESS_TOKEN", nothing)
    end
    if access_token === nothing
        conf = ConfParse("secrets.http")
        parse_conf!(conf)
        access_token = retrieve(conf, "access_token")
    end
    if access_token === nothing
        println("Error: Could not find access token for Dropbxo")
    end
    Authorization(access_token)
end



function post_rpc(auth::Authorization,
                  fun::String,
                  args::Union{Nothing, Dict} = nothing)::Union{Error, Dict}
    headers = ["Authorization" => "Bearer $(auth.access_token)",
               ]
    if args !== nothing
        push!(headers, "Content-Type" => "application/json")
        body = JSON.json(args)
    else
        body = HTTP.nobody
    end
    try
        resp = HTTP.request(
            "POST", "https://api.dropboxapi.com/2/$fun", headers, body;
            verbose=0)
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        return res
    catch ex
        ex::HTTP.StatusError
        resp = ex.response
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        println("Error $(ex.status): $(res["error_summary"])")
        return Error(res)
    end
end



function post_content_upload(auth::Authorization,
                             fun::String,
                             args::Union{Nothing, Dict},
                             content::Vector{UInt8})::Union{Error, Dict}
    headers = ["Authorization" => "Bearer $(auth.access_token)",
               ]
    push!(headers, "Dropbox-API-Arg" => JSON.json(args))
    push!(headers, "Content-Type" => "application/octet-stream")
    body = content
    try
        resp = HTTP.request(
            "POST", "https://content.dropboxapi.com/2/$fun", headers, body;
            verbose=0)
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        return res
    catch ex
        ex::HTTP.StatusError
        resp = ex.response
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        println("Error $(ex.status): $(res["error_summary"])")
        return Error(res)
    end
end



function post_content_download(auth::Authorization,
                               fun::String,
                               args::Union{Nothing, Dict})::
    Union{Error, Tuple{Dict, Vector{UInt8}}}
    headers = ["Authorization" => "Bearer $(auth.access_token)",
               ]
    push!(headers, "Dropbox-API-Arg" => JSON.json(args))
    push!(headers, "Content-Type" => "application/octet-stream")
    try
        resp = HTTP.request(
            "POST", "https://content.dropboxapi.com/2/$fun", headers;
            verbose=0)
        resp2 = Dict(lowercase(key) => value for (key, value) in resp.headers)
        res = JSON.parse(String(resp2["dropbox-api-result"]);
                         dicttype=Dict, inttype=Int64)
        return res, resp.body
    catch ex
        @show ex
        ex::HTTP.StatusError
        resp = ex.response
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        println("Error $(ex.status): $(res["error_summary"])")
        return Error(res)
    end
end



################################################################################



function files_create_folder(auth::Authorization,
                             path::String)::Union{Error, Nothing}
    args = Dict(
        "path" => path,
        "autorename" => false,
    )
    res = post_rpc(auth, "files/create_folder", args)
    if res isa Error return res end
    return nothing
end



function files_delete(auth::Authorization,
                      path::String)::Union{Error, Nothing}
    args = Dict(
        "path" => path,
        # parent_rev
    )
    res = post_rpc(auth, "files/delete", args)
    if res isa Error return res end
    return nothing
end



abstract type Metadata end
Metadata(d::Dict) = Dict(
    "file" => FileMetadata,
    "folder" => FolderMetadata,
    "deleted" => DeletedMetadata,
)[d[".tag"]](d)

struct MediaInfo end            # TODO
struct SymlinkInfo end          # TODO
struct FileSharingInfo end      # TODO
struct PropertyGroup end        # TODO

struct FileMetadata <: Metadata
    name::String
    id::String
    client_modified::String
    server_modified::String
    rev::String
    size::Int64
    path_lower::Union{Nothing, String}
    path_display::Union{Nothing, String}
    media_info::Union{Nothing, MediaInfo}
    symlink_info::Union{Nothing, SymlinkInfo}
    sharing_info::Union{Nothing, FileSharingInfo}
    property_groups::Union{Nothing, Vector{PropertyGroup}}
    has_explicit_shared_members::Union{Nothing, Bool}
    content_hash::Union{Nothing, String}
end
FileMetadata(d::Dict) = FileMetadata(
    d["name"],
    d["id"],
    d["client_modified"],
    d["server_modified"],
    d["rev"],
    d["size"],
    get(d, "path_lower", nothing),
    get(d, "path_display", nothing),
    nothing,                    # TODO
    nothing,                    # TODO
    nothing,                    # TODO
    nothing,                    # TODO
    get(d, "has_explicit_shared_members", nothing),
    get(d, "content_hash", nothing)
)

struct FolderSharingInfo end    # TODO

struct FolderMetadata <: Metadata
    name::String
    id::String
    path_lower::Union{Nothing, String}
    path_display::Union{Nothing, String}
    sharing_info::Union{Nothing, FolderSharingInfo}
    property_groups::Union{Nothing, Vector{PropertyGroup}}
end
FolderMetadata(d::Dict) = FolderMetadata(
    d["name"],
    d["id"],
    get(d, "path_lower", nothing),
    get(d, "path_display", nothing),
    nothing,                    # TODO
    nothing                     # TODO
)

struct DeletedMetadata <: Metadata
    name::String
    path_lower::Union{Nothing, String}
    path_display::Union{Nothing, String}
end
DeletedMetadata(d::Dict) = DeletedMetadata(
    d["name"],
    get(d, "path_lower", nothing),
    get(d, "path_display", nothing)
)

function files_list_folder(auth::Authorization,
                           path::String;
                           recursive::Bool = false)::
    Union{Error, Vector{Metadata}}
    args = Dict(
        "path" => path,
        "recursive" => recursive,
        "include_media_info" => false,
        "include_deleted" => false,
        "include_has_explicit_shared_members" => false,
        "include_mounted_folders" => true,
    )
    res = post_rpc(auth, "files/list_folder", args)
    if res isa Error return res end
    @assert !res["has_more"]
    return Metadata[Metadata(x) for x in res["entries"]]
end



function files_download(auth::Authorization,
                        path::String)::
    Union{Error, Tuple{FileMetadata, Vector{UInt8}}}
    args = Dict(
        "path" => path,
    )
    res = post_content_download(auth, "files/download", args)
    if res isa Error return res end
    res, content = res
    return FileMetadata(res), content
end



@enum WriteMode add overwrite # update

function files_upload(auth::Authorization,
                      path::String,
                      content::Vector{UInt8})::Union{Error, FileMetadata}
    args = Dict(
        "path" => path,
        "mode" => add,
        "autorename" => false,
        # "client_modified"
        "mute" => false,
        # "property_groups"
        "strict_conflict" => false,
    )
    res = post_content_upload(auth, "files/upload", args, content)
    if res isa Error return res end
    return FileMetadata(res)
end



struct Name
    given_name::String
    surname::String
    familiar_name::String
    display_name::String
    abbreviated_name::String
end
Name(d::Dict) = Name(
    d["given_name"],
    d["surname"],
    d["familiar_name"],
    d["display_name"],
    d["abbreviated_name"],)

@enum AccountType basic pro business
AccountType(d::Dict) = Dict(
    "basic" => basic,
    "pro" => pro,
    "business" => business,
)[d[".tag"]]

abstract type RootInfo end
RootInfo(d::Dict) = Dict(
    "team" => TeamRootInfo,
    "user" => UserRootInfo,
)[d[".tag"]](d)

struct TeamRootInfo <: RootInfo
    root_namespace_id::String
    home_namespace_id::String
    home_path::String
end
TeamRootInfo(d::Dict) = TeamRootInfo(
    d["root_namespace_id"],
    d["home_namespace_id"],
    d["home_path"],
)

struct UserRootInfo <: RootInfo
    root_namespace_id::String
    home_namespace_id::String
end
UserRootInfo(d::Dict) = UserRootInfo(
    d["root_namespace_id"],
    d["home_namespace_id"],
)

@enum SharedFolderMemberPolicy team anyone
SharedFolderMemberPolicy(d::Dict) = Dict(
    "team" => team,
    "anyone" => anyone,
)[d[".tag"]]

@enum SharedFolderJoinPolicy from_team_only from_anyone
SharedFolderJoinPolicy(d::Dict) = Dict(
    "from_team_only" => from_team_only,
    "from_anyone" => from_anyone,
)[d[".tag"]]

@enum SharedLinkCreatePolicy default_public default_team_only team_only
SharedLinkCreatePolicy(d::Dict) = Dict(
    "default_public" => default_public,
    "default_team_only" => default_team_only,
    "team_only" => team_only,
)[d[".tag"]]

struct TeamSharingPolicies
    shared_folder_member_policy::SharedFolderMemberPolicy
    shared_folder_join_policy::SharedFolderJoinPolicy
    shared_link_create_policy::SharedLinkCreatePolicy
end
TeamSharingPolicies(d::Dict) = TeamSharingPolicies(
    SharedFolderMemberPolicy(d["shared_folder_member_policy"]),
    SharedFolderJoinPolicy(d["shared_folder_join_policy"]),
    SharedLinkCreatePolicy(d["shared_link_create_policy"]),
)

@enum OfficeAddInPolicy disabled enabled
OfficeAddInPolicy(d::Dict) = Dict(
    "disabled" => disabled,
    "enabled" => enabled,
)[d[".tag"]]

struct FullTeam
    id::String
    name::String
    sharing_policies::TeamSharingPolicies
    office_addin_policy::OfficeAddInPolicy
end
FullTeam(d::Dict) = FullTeam(
    d["id"],
    d["name"],
    TeamSharingPolicies(d["sharing_policies"]),
    OfficeAddInPolicy(d["office_addin_policy"]),
)

struct FullAccount
    account_id::String
    name::Name
    email::String
    email_verified::Bool
    disabled::Bool
    locale::String
    referral_link::String
    is_paired::Bool
    account_type::AccountType
    root_info::RootInfo
    profile_photo_url::Union{Nothing, String}
    country::Union{Nothing, String}
    team::Union{Nothing, FullTeam}
    team_member_id::Union{Nothing, String}
end
FullAccount(d::Dict) = FullAccount(
    d["account_id"],
    Name(d["name"]),
    d["email"],
    d["email_verified"],
    d["disabled"],
    d["locale"],
    d["referral_link"],
    d["is_paired"],
    AccountType(d["account_type"]),
    RootInfo(d["root_info"]),
    get(d, "profile_photo_url", nothing),
    get(d, "country", nothing),
    mapget(x->FullTeam(x), d, "team"),
    get(d, "team_member_id", nothing),
)

function users_get_current_account(auth::Authorization)::
    Union{Error, FullAccount}
    res = post_rpc(auth, "users/get_current_account")
    if res isa Error return res end
    return FullAccount(res)
end



abstract type SpaceAllocation end
SpaceAllocation(d::Dict) = Dict(
    "individual" => IndividualSpaceAllocation,
    "team" => TeamSpaceAllocation,
)[d[".tag"]](d)

struct IndividualSpaceAllocation <: SpaceAllocation
    allocated::Int64
end
IndividualSpaceAllocation(d::Dict) = IndividualSpaceAllocation(
    d["allocated"],
)

@enum MemberSpaceLimitType off alert_only stop_sync
MemberSpaceLimitType(d::Dict) = Dict(
    "off" => off,
    "alert_only" => alert_only,
    "stop_sync" => stop_sync,
)[d[".tag"]]

struct TeamSpaceAllocation <: SpaceAllocation
    used::Int64
    allocated::Int64
    user_within_team_space_allocated::Int64
    user_within_team_space_limit_type::MemberSpaceLimitType
end
TeamSpaceAllocation(d::Dict) = TeamSpaceAllocation(
    d["used"],
    d["allocated"],
    d["user_within_team_space_allocated"],
    MemberSpaceLimitType(d["user_within_team_space_limit_type"]),
)

struct SpaceUsage
    used::Int64
    allocation::SpaceAllocation
end
SpaceUsage(d::Dict) = SpaceUsage(
    d["used"],
    SpaceAllocation(d["allocation"]),
)

function users_get_space_usage(auth::Authorization)::Union{Error, SpaceUsage}
    res = post_rpc(auth, "users/get_space_usage")
    if res isa Error return res end
    return SpaceUsage(res)
end



function main()
    auth = read_authorization()

    println("Getting current account...")
    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    println("    account: name: $first $last ($display)")

    println("Getting space usage...")
    usage = users_get_space_usage(auth)
    used = usage.used
    println("    usage: $(round(Int, used / 1.0e9)) GByte")

    filename(entry) =
        entry.path_display === nothing ? entry.name : entry.path_display

    println("Listing folder...")
    entries = files_list_folder(auth, "", recursive=true)
    for (i,entry) in enumerate(entries)
        println("    $i: $(filename(entry))")
    end

    println("Creating folder...")
    files_create_folder(auth, "/folder")

    println("Listing folder...")
    entries = files_list_folder(auth, "", recursive=true)
    for (i,entry) in enumerate(entries)
        println("    $i: $(filename(entry))")
    end

    println("Uploading file...")
    files_upload(auth, "/folder/file", Vector{UInt8}("Hello, World!\n"))

    println("Listing folder...")
    entries = files_list_folder(auth, "", recursive=true)
    for (i,entry) in enumerate(entries)
        println("    $i: $(filename(entry))")
    end

    println("Downloading file...")
    metadata, content = files_download(auth, "/folder/file")
    @assert String(content) == "Hello, World!\n"

    println("Deleting folder...")
    files_delete(auth, "/folder")

    println("Listing folder...")
    entries = files_list_folder(auth, "", recursive=true)
    for (i,entry) in enumerate(entries)
        println("    $i: $(filename(entry))")
    end

    println("Done.")
end

end
