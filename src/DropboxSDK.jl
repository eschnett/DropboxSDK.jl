module DropboxSDK

# using Base.Iterators
using ConfParser
using HTTP
using JSON



"""
    mapget(fun::Function, dict::Dict, key, def=nothing)

Get an entry from a dictionary, and apply the function `fun` to the
result. If the key `key` is missing from the dictionary, return the
default value `def`.
"""
function mapget(fun::Function, dict::Dict, key, def=nothing)
    value = get(dict, key, nothing)
    if value === nothing return def end
    fun(value)
end



################################################################################



export Error
"""
    struct Error
        dict::Dict{String, Any}
    end

Return value if a request failed. The content is a dictionary
containing the parsed JSON error response.
"""
struct Error
    dict::Dict{String, Any}
end



export Authorization
"""
    struct Authorization
        access_token::String
    end

Contains an access token. Almost all Dropbox API functions require
such a token. Access tokens are like passwords and should be treated
with the same care.
"""
struct Authorization
    access_token::String
end

export get_authorization
"""
    get_authorization()::Authorization

Get an authorization token. This function first looks for an
environment values `DROPBOXSDK_ACCESS_TOKEN`, and then for a file
`secrets.http` in the current directory. If neither exists, this is an
error.
"""
function get_authorization()::Authorization
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
        error("Could not find access token for Dropbox")
    end
    Authorization(access_token)
end



################################################################################



"""
    post_rpc(auth::Authorization,
             fun::String,
             args::Union{Nothing, Dict} = nothing)::Union{Error, Dict}

Post an RPC request to the Dropbox API.
"""
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
        @show ex
        ex::HTTP.StatusError
        resp = ex.response
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        println("Error $(ex.status): $(res["error_summary"])")
        return Error(res)
    end
end



"""
    post_content_upload(auth::Authorization,
                        fun::String,
                        args::Union{Nothing, Dict} = nothing
                       )::Union{Error, Dict}

Post a Content Upload request to the Dropbox API.
"""
function post_content_upload(auth::Authorization,
                             fun::String,
                             args::Union{Nothing, Dict},
                             content::Vector{UInt8})::
    Union{Error, Nothing, Dict}

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



"""
    post_content_download(auth::Authorization,
                          fun::String,
                          args::Union{Nothing, Dict} = nothing)::Union{Error, Dict}

Post a Content Download request to the Dropbox API.
"""
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
        ex::HTTP.StatusError
        resp = ex.response
        res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
        println("Error $(ex.status): $(res["error_summary"])")
        return Error(res)
    end
end



################################################################################



export files_create_folder
"""
    files_create_folder(auth::Authorization,
                        path::String
                       )::Union{Error, Nothing}

Create a folder `path`.
"""
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



export files_delete
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



export Metadata
abstract type Metadata end
Metadata(d::Dict) = Dict(
    "file" => FileMetadata,
    "folder" => FolderMetadata,
    "deleted" => DeletedMetadata,
)[d[".tag"]](d)

export MediaInfo, SymlinkInfo, FileSharingInfo, PropertyGroup
struct MediaInfo end            # TODO
struct SymlinkInfo end          # TODO
struct FileSharingInfo end      # TODO
struct PropertyGroup end        # TODO

export FileMetadata
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

export FolderSharingInfo
struct FolderSharingInfo end    # TODO

export FolderMetadata
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

export DeletedMetadata
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

export files_list_folder
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



export files_download
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



export WriteMode
@enum WriteMode add overwrite # update

export files_upload
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

export StatefulIterator
struct StatefulIterator{T}
    # A stateful iterator that returns values of type T
    iterator::Iterators.Stateful{C, Union{Nothing, Tuple{T, S}}} where {C, S}
    # function StatefulIterator{T}(
    #     iter::Iterators.Stateful{C, Union{Nothing, Tuple{T, S}}}) where
    #     {T, C, S}
    #     
    #     return new{T, C, S}(iter)
    # end
    function StatefulIterator{T}(coll) where {T}
        return new{T}(Iterators.Stateful(coll))
    end
end

export ContentIterator
const ContentIterator = StatefulIterator{Vector{UInt8}}

function files_upload(auth::Authorization,
                      path::String,
                      content::ContentIterator)::Union{Error, FileMetadata}
    session_id = nothing
    offset = Int64(0)
    while !isempty(content.iterator)
        chunk = popfirst!(content.iterator)::Vector{UInt8}
        isempty(chunk) && continue
        if session_id === nothing
            args = Dict(
                "close" => false,
            )
            res = post_content_upload(auth, "files/upload_session/start",
                                      args, chunk)
            if res isa Error return res end
            session_id = res["session_id"]
            offset = offset + length(chunk)
        else
            args = Dict(
                "cursor" => Dict(
                    "session_id" => session_id,
                    "offset" => offset,
                ),
                "close" => false,
            )
            res = post_content_upload(auth, "files/upload_session/append_v2",
                                      args, chunk)
            if res isa Error return res end
            offset = offset + length(chunk)
        end
    end
    if session_id !== nothing
        # We don't need to close the session
        # args = Dict(
        #     "cursor" => Dict(
        #         "session_id" => session_id,
        #         "offset" => offset,
        #     ),
        #     "close" => true,
        # )
        # res = post_content_upload(auth, "files/upload_session/append_v2",
        #                           args, UInt8[])
        # if res isa Error return res end
        args = Dict(
            "cursor" => Dict(
                "session_id" => session_id,
                "offset" => offset,
            ),
            "commit" => Dict(
                "path" => path,
                "mode" => add,
                "autorename" => false,
                # "client_modified"
                "mute" => false,
                # "property_groups"
                "strict_conflict" => false,
            ),
        )
        res = post_content_upload(auth, "files/upload_session/finish",
                                  args, UInt8[])
        if res isa Error return res end
        return FileMetadata(res)
    end
    # The file was empty
    @assert offset = 0
    return files_upload(auth, path, UInt8[])
end

function files_upload(
    auth::Authorization,
    contents::StatefulIterator{Tuple{String, ContentIterator}})::
    Union{Error, Vector{Union{Error, FileMetadata}}}
    
    # TODO: Define Cursor (and Commit) structs instead
    paths = String[]
    session_ids = String[]
    offsets = Int64[]
    # TODO: can handle only 1000 files at once
    # TODO: parallelize loop
    for (path, content) in contents.iterator

        session_id = nothing
        offset = Int64(0)
        while !isempty(content.iterator)
            chunk = popfirst!(content.iterator)::Vector{UInt8}
            isempty(chunk) && continue
            if session_id === nothing
                args = Dict(
                    "close" => false,
                )
                res = post_content_upload(auth, "files/upload_session/start",
                                          args, chunk)
                if res isa Error return res end
                session_id = res["session_id"]
                offset = offset + length(chunk)
            else
                args = Dict(
                    "cursor" => Dict(
                        "session_id" => session_id,
                        "offset" => offset,
                    ),
                    "close" => false,
                )
                res = post_content_upload(auth,
                                          "files/upload_session/append_v2",
                                          args, chunk)
                if res isa Error return res end
                offset = offset + length(chunk)
            end
        end
        # TODO: We need to close only the last session
        if session_id === nothing
            # The file is empty
            @assert offset == 0
            args = Dict(
                "close" => true,
            )
            res = post_content_upload(auth, "files/upload_session/start",
                                      args, UInt8[])
            if res isa Error return res end
            session_id = res["session_id"]
        else
            args = Dict(
                "cursor" => Dict(
                    "session_id" => session_id,
                    "offset" => offset,
                ),
                "close" => true,
            )
            res = post_content_upload(auth, "files/upload_session/append_v2",
                                      args, UInt8[])
            if res isa Error return res end
        end

        push!(paths, path)
        push!(session_ids, session_id)
        push!(offsets, offset)
    end

    if isempty(paths)
        # We uploaded zero files
        return Union{Error, FileMetadata}[]
    end

    entries = []
    for (path, session_id, offset) in zip(paths, session_ids, offsets)
        args = Dict(
            "cursor" => Dict(
                "session_id" => session_id,
                "offset" => offset,
            ),
            "commit" => Dict(
                "path" => path,
                "mode" => add,
                "autorename" => false,
                # "client_modified"
                "mute" => false,
                # "property_groups"
                "strict_conflict" => false,
            ),
        )
        push!(entries, args)
    end
    args = Dict(
        "entries" => entries,
    )
    res = post_rpc(auth, "files/upload_session/finish_batch", args)
    if res isa Error return res end
    async_job_id = res["async_job_id"]

    is_in_progress = true    
    delay = 1.0                 # seconds
    while is_in_progress
        sleep(delay)
        delay = min(60.0, 2.0 * delay) # exponential back-off
        args = Dict(
            "async_job_id" => async_job_id,
        )
        res = post_rpc(auth, "files/upload_session/finish_batch/check", args)
        if res isa Error return res end
        is_in_progress = res[".tag"] == "in_progress"
    end
    @assert res[".tag"] == "complete"

    return Union{Error, FileMetadata}[
        entry[".tag"] == "success" ? FileMetadata(entry) : Error(entry)
        for entry in res["entries"]
    ]
end



export Name
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

export AccountType
@enum AccountType basic pro business
AccountType(d::Dict) = Dict(
    "basic" => basic,
    "pro" => pro,
    "business" => business,
)[d[".tag"]]

export RootInfo
abstract type RootInfo end
RootInfo(d::Dict) = Dict(
    "team" => TeamRootInfo,
    "user" => UserRootInfo,
)[d[".tag"]](d)

export TeamRootInfo
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

export UserRootInfo
struct UserRootInfo <: RootInfo
    root_namespace_id::String
    home_namespace_id::String
end
UserRootInfo(d::Dict) = UserRootInfo(
    d["root_namespace_id"],
    d["home_namespace_id"],
)

export SharedFolderMemberPolicy
@enum SharedFolderMemberPolicy team anyone
SharedFolderMemberPolicy(d::Dict) = Dict(
    "team" => team,
    "anyone" => anyone,
)[d[".tag"]]

export SharedFolderJoinPolicy
@enum SharedFolderJoinPolicy from_team_only from_anyone
SharedFolderJoinPolicy(d::Dict) = Dict(
    "from_team_only" => from_team_only,
    "from_anyone" => from_anyone,
)[d[".tag"]]

export SharedLinkCreatePolicy
@enum SharedLinkCreatePolicy default_public default_team_only team_only
SharedLinkCreatePolicy(d::Dict) = Dict(
    "default_public" => default_public,
    "default_team_only" => default_team_only,
    "team_only" => team_only,
)[d[".tag"]]

export TeamSharingPolicies
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

export OfficeAddInPolicy
@enum OfficeAddInPolicy disabled enabled
OfficeAddInPolicy(d::Dict) = Dict(
    "disabled" => disabled,
    "enabled" => enabled,
)[d[".tag"]]

export FullTeam
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

export FullAccount
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

export users_get_current_account
function users_get_current_account(auth::Authorization)::
    Union{Error, FullAccount}

    res = post_rpc(auth, "users/get_current_account")
    if res isa Error return res end
    return FullAccount(res)
end



export SpaceAllocation
abstract type SpaceAllocation end
SpaceAllocation(d::Dict) = Dict(
    "individual" => IndividualSpaceAllocation,
    "team" => TeamSpaceAllocation,
)[d[".tag"]](d)

export IndividualSpaceAllocation
struct IndividualSpaceAllocation <: SpaceAllocation
    allocated::Int64
end
IndividualSpaceAllocation(d::Dict) = IndividualSpaceAllocation(
    d["allocated"],
)

export MemberSpaceLimitType
@enum MemberSpaceLimitType off alert_only stop_sync
MemberSpaceLimitType(d::Dict) = Dict(
    "off" => off,
    "alert_only" => alert_only,
    "stop_sync" => stop_sync,
)[d[".tag"]]

export TeamSpaceAllocation
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

export SpaceUsage
struct SpaceUsage
    used::Int64
    allocation::SpaceAllocation
end
SpaceUsage(d::Dict) = SpaceUsage(
    d["used"],
    SpaceAllocation(d["allocation"]),
)

export users_get_space_usage
function users_get_space_usage(auth::Authorization)::Union{Error, SpaceUsage}
    res = post_rpc(auth, "users/get_space_usage")
    if res isa Error return res end
    return SpaceUsage(res)
end

end
