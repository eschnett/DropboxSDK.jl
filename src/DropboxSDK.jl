module DropboxSDK

# using Base.Iterators
using ConfParser
using HTTP
using JSON
using SHA



"""
    geteuid()::Int

Call the Unix `geteuid` function.
"""
geteuid()::Int = ccall(:geteuid, Cint, ())
"""
    getuid()::Int

Call the Unix `getuid` function.
"""
getuid()::Int = ccall(:getuid, Cint, ())



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



function takeifready!(ch::Channel{T})::Union{Nothing, T} where {T}
    if !isready(ch)
        return nothing
    end
    take!(ch)
end



include("types.jl")



################################################################################



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
        try
            # Ensure that the file containing the access token is a
            # simple file, is owned by the user, and is only
            # accessible by the user
            filename = joinpath(homedir(), ".dropboxsdk.http")
            st = stat(filename)
            if ispath(st)
                if !isfile(st)
                    println("Configuration file \"$filename\" exists,",
                            " but is not a file")
                elseif st.uid != geteuid()
                    println("Configuration file \"$filename\" exists,",
                            " but is not owned by the current effective user")
                elseif filemode(st) & 0o077 != 0
                    println("Configuration file \"$filename\" exists,",
                            " but is accessible by others")
                else
                    conf = ConfParse(filename)
                    parse_conf!(conf)
                    access_token = retrieve(conf, "access_token")
                end
            end
        catch
        end
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
             args::Union{Nothing, Dict} = nothing
            )::Dict

Post an RPC request to the Dropbox API.
"""
function post_rpc(auth::Authorization,
                  fun::String,
                  args::Union{Nothing, Dict} = nothing)::Dict
    headers = ["Authorization" => "Bearer $(auth.access_token)",
               ]
    if args !== nothing
        push!(headers, "Content-Type" => "application/json")
        body = JSON.json(args)
    else
        body = HTTP.nobody
    end

    # We might need to retry several times
    while true
        try
            resp = HTTP.request(
                "POST", "https://api.dropboxapi.com/2/$fun", headers, body;
                verbose=0)
            res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
            return res
        catch ex
            if ex isa HTTP.StatusError
                resp = ex.response
                res = JSON.parse(String(resp.body);
                                 dicttype=Dict, inttype=Int64)

                # Should we retry?
                resp2 = Dict(lowercase(key) => value
                             for (key, value) in resp.headers)
                retry_after = mapget(s->parse(Float64, s), resp2, "retry-after")
                if retry_after !== nothing
                    println("Info: Error $(ex.status): $(res["error_summary"])")
                    println("Info: Waiting $retry_after seconds...")
                    sleep(retry_after)
                    println("Info: Retrying...")
                    continue
                end

                throw(DropboxError(res))
            end
            rethrow(ex)
        end
    end
end



"""
    post_content_upload(auth::Authorization,
                        fun::String,
                        args::Union{Nothing, Dict} = nothing
                       )::Dict

Post a Content Upload request to the Dropbox API.
"""
function post_content_upload(auth::Authorization,
                             fun::String,
                             args::Union{Nothing, Dict},
                             content::Vector{UInt8})::Union{Nothing, Dict}
    headers = ["Authorization" => "Bearer $(auth.access_token)",
               ]
    push!(headers, "Dropbox-API-Arg" => JSON.json(args))
    push!(headers, "Content-Type" => "application/octet-stream")
    body = content

    # We might need to retry several times
    while true
        try
            resp = HTTP.request(
                "POST", "https://content.dropboxapi.com/2/$fun", headers, body;
                verbose=0)
            res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
            return res
        catch ex
            if ex isa HTTP.StatusError
                resp = ex.response
                res = JSON.parse(String(resp.body);
                                 dicttype=Dict, inttype=Int64)

                # Should we retry?
                resp2 = Dict(lowercase(key) => value
                             for (key, value) in resp.headers)
                retry_after = mapget(s->parse(Float64, s), resp2, "retry-after")
                if retry_after !== nothing
                    println("Warning $(ex.status): $(res["error_summary"])")
                    println("Waiting $retry_after seconds...")
                    sleep(retry_after)
                    println("Retrying...")
                    continue
                end

                throw(DropboxError(res))
            end
            rethrow(ex)
        end
    end
end



"""
    post_content_download(auth::Authorization,
                          fun::String,
                          args::Union{Nothing, Dict} = nothing
                         )::Tuple{Dict, Vector{UInt8}}

Post a Content Download request to the Dropbox API.
"""
function post_content_download(auth::Authorization,
                               fun::String,
                               args::Union{Nothing, Dict}
                               )::Tuple{Dict, Vector{UInt8}}
    headers = ["Authorization" => "Bearer $(auth.access_token)",
               ]
    push!(headers, "Dropbox-API-Arg" => JSON.json(args))
    push!(headers, "Content-Type" => "application/octet-stream")

    # We might need to retry several times
    while true
        try
            resp = HTTP.request(
                "POST", "https://content.dropboxapi.com/2/$fun", headers;
                verbose=0)
            resp2 = Dict(lowercase(key) => value
                         for (key, value) in resp.headers)
            res = JSON.parse(String(resp2["dropbox-api-result"]);
                             dicttype=Dict, inttype=Int64)
            return res, resp.body
        catch ex
            if ex isa HTTP.StatusError
                resp = ex.response
                res = JSON.parse(String(resp.body);
                                 dicttype=Dict, inttype=Int64)

                # Should we retry?
                resp2 = Dict(lowercase(key) => value
                             for (key, value) in resp.headers)
                retry_after = mapget(s->parse(Float64, s), resp2, "retry-after")
                if retry_after !== nothing
                    println("Warning $(ex.status): $(res["error_summary"])")
                    println("Waiting $retry_after seconds...")
                    sleep(retry_after)
                    println("Retrying...")
                    continue
                end

                throw(DropboxError(res))
            end
            rethrow(ex)
        end
    end
end



################################################################################



export calc_content_hash
"""
    calc_content_hash(data::Vector{UInt8})::String

Calculate the content hash of a byte array with Dropbox's algorithm.
"""
function calc_content_hash(data::AbstractVector{UInt8})::String
    chunksums = UInt8[]
    chunksize = 4 * 1024 * 1024
    len = length(data)
    for offset in 1:chunksize:len
        chunk = @view data[offset : min(len, offset+chunksize-1)]
        append!(chunksums, sha256(chunk))
    end
    bytes2hex(sha256(chunksums))
end



export calc_content_hash_start
"""
    calc_content_hash_start()::Tuple{Channel{AbstractVector{UInt8}}
                                     Channel{String}}

Start a task to calculate a content hash with Dropbox's algorithm from
chunks of data. Returns two channels: One channel to pass in data in
chunks, and the other channel will hold the result after the first
channel is closed.
"""
function calc_content_hash_start()::Tuple{Channel{AbstractVector{UInt8}},
                                          Channel{String}}
    content_hash_channel = Channel{String}(0)
    function task(data_channel::Channel{AbstractVector{UInt8}})
        chunksize = 4 * 1024 * 1024
        chunksums = UInt8[]
        # TODO: Don't buffer the data; instead, use SHA256_CTX to
        # handle partial chunks
        buffer = UInt8[]
        for data in data_channel
            append!(buffer, data)
            len = length(buffer)
            if len >= chunksize
                for offset in 1 : chunksize : len-chunksize+1
                    chunk = @view buffer[offset : offset+chunksize-1]
                    append!(chunksums, sha256(chunk))
                end
                newlen = mod(len, chunksize)
                buffer = buffer[end-newlen+1 : end]
            end
        end
        if !isempty(buffer)
            append!(chunksums, sha256(buffer))
        end
        put!(content_hash_channel, bytes2hex(sha256(chunksums)))
        close(content_hash_channel)
    end
    data_channel = Channel(task, ctype=AbstractVector{UInt8})
    data_channel, content_hash_channel
end



export files_create_folder
"""
    files_create_folder(auth::Authorization,
                        path::String
                       )::FolderMetadata

Create a folder `path`. Returns metadata for the created folder.
"""
function files_create_folder(auth::Authorization,
                             path::String)::FolderMetadata
    args = Dict(
        "path" => path,
        "autorename" => false,
    )
    res = post_rpc(auth, "files/create_folder", args)
    return FolderMetadata(res)
end



export files_delete
"""
    files_delete(auth::Authorization,
                 path::String
                )::Metadata

Delete a file or folder `path` recursively. Returns metadata of the
deleted object.
"""
function files_delete(auth::Authorization,
                      path::String)::Metadata
    args = Dict(
        "path" => path,
        # parent_rev
    )
    res = post_rpc(auth, "files/delete", args)
    return Metadata(res)
end



export files_download
"""
    files_download(auth::Authorization,
                   path::String
                  )::Tuple{FileMetadata, Vector{UInt8}}

Download file `path`. Returns both its metadata and content.
"""
function files_download(auth::Authorization,
                        path::String)::Tuple{FileMetadata, Vector{UInt8}}

    args = Dict(
        "path" => path,
    )
    res, content = post_content_download(auth, "files/download", args)
    metadata = FileMetadata(res)

    # Check content hash
    content_hash = calc_content_hash(content)
    if metadata.content_hash != content_hash
        throw(DropboxError(
            Dict("error" => "LocalContentHashMismatch",
                 "error_summary" => "local/content_hashes_do_not_match",
                 "path" => path,
                 "content_hash" => metadata.content_hash,
                 "local_content_hash" => content_hash,
                 )))
    end

    return metadata, content
end



export files_get_metadata
"""
    files_get_metadata(auth::Authorization,
                       path::String
                      )::Metadata

Get metadata for file or folder `path`.
"""
function files_get_metadata(auth::Authorization,
                            path::String)::Metadata
    args = Dict(
        "path" => path,
        "include_media_info" => false,
        "include_deleted" => false,
        "include_has_explicit_shared_members" => false,
        # "include_property_groups"
    )
    res = post_rpc(auth, "files/get_metadata", args)
    return Metadata(res)
end



export files_list_folder
"""
    files_list_folder(auth::Authorization,
                      path::String;
                      recursive::Bool = false
                     )::Vector{Metadata}

List the contents of folder `path`.
"""
function files_list_folder(auth::Authorization,
                           path::String;
                           recursive::Bool = false)::Vector{Metadata}
    args = Dict(
        "path" => path,
        "recursive" => recursive,
        "include_media_info" => false,
        "include_deleted" => false,
        "include_has_explicit_shared_members" => false,
        "include_mounted_folders" => true,
    )
    res = post_rpc(auth, "files/list_folder", args)
    metadatas = Metadata[Metadata(x) for x in res["entries"]]
    cursor = res["cursor"]
    has_more = res["has_more"]

    while has_more
        args = Dict(
            "cursor" => cursor,
        )
        res = post_rpc(auth, "files/list_folder/continue", args)
        append!(metadatas, Metadata[Metadata(x) for x in res["entries"]])
        cursor = res["cursor"]
        has_more = res["has_more"]
    end

    return metadatas
end



export WriteMode
@enum WriteMode add overwrite # update

export files_upload
"""
    files_upload(auth::Authorization,
                 path::String,
                 content::Vector{UInt8}
                )::FileMetadata

Upload the byte array `content` to a file `path`, returning its
metadata. This function should only be used for small files (< 150
MByte), and if only a few files are uploaded. Other `files_upload`
functions are more efficient for large files and/or if there are many
files to be uploaded.
"""
function files_upload(auth::Authorization,
                      path::String,
                      content::Vector{UInt8})::FileMetadata
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
    metadata = FileMetadata(res)

    # Check content hash
    content_hash = calc_content_hash(content)
    if metadata.content_hash != content_hash
        throw(DropboxError(
            Dict("error" => "LocalContentHashMismatch",
                 "error_summary" => "local/content_hashes_do_not_match",
                 "path" => path,
                 "content_hash" => metadata.content_hash,
                 "local_content_hash" => content_hash,
                 )))
    end

    return metadata
end



export files_upload_start
"""
    files_upload_start(auth::Authorization,
                       path::String,
                      )::Tuple{Channel{Vector{UInt8}},
                               Channel{FileMetadata}}

Start uploadin a file `path`. Returns two channels. The first channel
is used to pass in data in chunks, where each chunk should be no
larger than 150 MByte. This channel needs to be closed after passing
in all chunks to finalize the upload. The second channel will then
hold the metadata of the uploaded file.

This function should only be used if only a few files are to be
uploaded. Other `files_upload_start` functions are more efficient if
there are many files to be uploaded.
"""
function files_upload_start(auth::Authorization,
                            path::String
                            )::Tuple{Channel{Vector{UInt8}},
                                     Channel{FileMetadata}}
    metadata_channel = Channel{FileMetadata}(0)
    function task(upload_channel::Channel{Vector{UInt8}})
        session_id = nothing
        offset = Int64(0)
        data_channel, content_hash_channel = calc_content_hash_start()
        for chunk in upload_channel
            isempty(chunk) && continue
            if session_id === nothing
                args = Dict(
                    "close" => false,
                )
                res = post_content_upload(auth, "files/upload_session/start",
                                          args, chunk)
                session_id = res["session_id"]
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
            end
            offset = offset + length(chunk)
            put!(data_channel, chunk)
        end
        if session_id === nothing
            # The file was empty
            @assert offset == 0
            metadata = files_upload(auth, path, UInt8[])
        else
            # Note: We don't need to close the session
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
            metadata = FileMetadata(res)
        end

        # Check content hash
        close(data_channel)
        content_hash = take!(content_hash_channel)
        if metadata.content_hash != content_hash
            throw(DropboxError(
                Dict("error" => "LocalContentHashMismatch",
                     "error_summary" => "local/content_hashes_do_not_match",
                     "path" => path,
                     "content_hash" => metadata.content_hash,
                     "local_content_hash" => content_hash,
                     )))
        end

        put!(metadata_channel, metadata)
        close(metadata_channel)
    end
    upload_channel = Channel(task, ctype=Vector{UInt8})
    upload_channel, metadata_channel
end



export UploadSpec
"""
    struct UploadSpec
        data_channel::Channel{Vector{UInt8}}
        destination::String
    end

Specify both content and path for a file that is to be uploaded. The
content needs to be passed in as chunks via a channel.
"""
struct UploadSpec
    data_channel::Channel{Vector{UInt8}}
    destination::String
end

mutable struct UploadState
    path::String
    session_id::String
    offset::Int64
    content_hash::String
    metadata::Union{Nothing, FileMetadata}
end

"""
    files_upload_start(auth::Authorization,
                      )::Tuple{Channel{UploadSpec},
                               Channel{Vector{FileMetadata}}}

Start uploading several files simultaneously in an efficient manner.
Returns two channels. The first channel is used to describe the files
that should be uploaded. This channel needs to be closed after passing
in all chunks to finalize the upload. The second channel will then
hold the metadata for all uploaded files.

This function is efficient if many files are uploaded.
"""
function files_upload_start(auth::Authorization
                            )::Tuple{Channel{UploadSpec},
                                     Channel{Vector{FileMetadata}}}
    metadatas_channel = Channel{Vector{FileMetadata}}(0)

    function task(upload_spec_channel::Channel{UploadSpec})
        upload_states = UploadState[]
        # TODO: can handle only 1000 files at once
        # TODO: parallelize loop

        function task1(upload_spec::UploadSpec,
                       result_channel::Channel{Nothing})
            session_id = nothing
            offset = Int64(0)
            data_channel, content_hash_channel = calc_content_hash_start()
            for chunk in upload_spec.data_channel
                isempty(chunk) && continue
                if session_id === nothing
                    args = Dict(
                        "close" => false,
                    )
                    res = post_content_upload(
                        auth, "files/upload_session/start",
                         args, chunk)
                    session_id = res["session_id"]
                else
                    args = Dict(
                        "cursor" => Dict(
                            "session_id" => session_id,
                            "offset" => offset,
                        ),
                        "close" => false,
                    )
                    res = post_content_upload(
                        auth, "files/upload_session/append_v2",
                        args, chunk)
                end
                offset = offset + length(chunk)
                put!(data_channel, chunk)
            end
            # TODO: We need to close only the last session. But what
            # does "last" mean? Is it "last session id passed to
            # files/finish_upload_batch", or the last session to
            # finish uploading?
            if session_id === nothing
                # The file is empty
                @assert offset == 0
                args = Dict(
                    "close" => true,
                )
                res = post_content_upload(
                    auth, "files/upload_session/start",
                    args, UInt8[])
                session_id = res["session_id"]
            else
                args = Dict(
                    "cursor" => Dict(
                        "session_id" => session_id,
                        "offset" => offset,
                    ),
                    "close" => true,
                )
                res = post_content_upload(
                    auth, "files/upload_session/append_v2",
                    args, UInt8[])
            end

            close(data_channel)
            content_hash = take!(content_hash_channel)
            push!(upload_states,
                  UploadState(upload_spec.destination, session_id,
                              offset, content_hash, nothing))

            put!(result_channel, nothing)
            close(result_channel)
        end

        tasks = Channel{Nothing}[]
        for upload_spec in upload_spec_channel
            push!(tasks, Channel(ch -> task1(upload_spec, ch), ctype=Nothing))
        end
        for t in tasks
            take!(t)
        end

        if isempty(upload_states)
            # We uploaded zero files
            put!(metadatas_channel, FileMetadata[])
            close(metadatas_channel)
            return
        end

        # We might need to retry several times
        while true

            missing_uploads = Int[]
            for (i, upload_state) in enumerate(upload_states)
                if upload_state.metadata isa Nothing
                    push!(missing_uploads, i)
                end
            end
            @assert !isempty(missing_uploads)

            entries = []
            for i in missing_uploads
                upload_state = upload_states[i]
                @assert upload_state.metadata isa Nothing
                args = Dict(
                    "cursor" => Dict(
                        "session_id" => upload_state.session_id,
                        "offset" => upload_state.offset,
                    ),
                    "commit" => Dict(
                        "path" => upload_state.path,
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
            is_complete = res[".tag"] == "complete"

            # Wait for completion
            if !is_complete
                async_job_id = res["async_job_id"]

                delay = 1.0         # seconds
                while !is_complete
                    sleep(delay)
                    delay = min(60.0, 2.0 * delay) # exponential back-off

                    args = Dict(
                        "async_job_id" => async_job_id,
                    )
                    res = post_rpc(auth,
                                   "files/upload_session/finish_batch/check",
                                   args)
                    is_complete = res[".tag"] == "complete"
                end
            end
            entries = res["entries"]

            @assert length(entries) == length(missing_uploads)
            for (i, entry) in zip(missing_uploads, entries)
                if entry[".tag"] == "success" 
                    # The tag is "success", but the type is actually
                    # "FileMetadata". This is strange, and also doesn't
                    # agree with the documentation.
                    success = entry
                    upload_state = upload_states[i]
                    @assert upload_state.metadata isa Nothing
    
                    metadata = FileMetadata(success)
                    if metadata.content_hash != upload_state.content_hash
                        throw(DropboxError(
                            Dict("error" => "LocalContentHashMismatch",
                                 "error_summary" =>
                                 "local/content_hashes_do_not_match",
                                 "path" => upload_state.path,
                                 "content_hash" => metadata.content_hash,
                                 "local_content_hash" =>
                                 upload_state.content_hash,
                                 )))
                    end
                    upload_state.metadata = metadata
                else
                    @assert entry[".tag"] == "failure"
                    failure = entry["failure"]
                    if failure[".tag"] == "too_many_write_operations"
                        # we will retry this entry
                    else
                        throw(DropboxError(failure))
                    end
                end
            end

            if any(upload_state.metadata isa Nothing
                   for upload_state in upload_states)
                println("Info: Error \"too_many_write_operations\"")
                println("Info: Waiting for 1 seconds...")
                sleep(1)
                println("Info: Retrying...")
                continue
            end
    
            metadatas = FileMetadata[upload_state.metadata
                                     for upload_state in upload_states]
            put!(metadatas_channel, metadatas)
            close(metadatas_channel)
            return

        end
    end

    upload_spec_channel = Channel(task, ctype=UploadSpec)
    upload_spec_channel, metadatas_channel
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
"""
    users_get_current_account(auth::Authorization)::FullAccount

Get information about the current account, i.e. the account associated
with the account token in the authorization `auth`.
"""
function users_get_current_account(auth::Authorization)::FullAccount
    res = post_rpc(auth, "users/get_current_account")
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
"""
    users_get_space_usage(auth::Authorization)::SpaceUsage

Get the space usage for the current account.
"""
function users_get_space_usage(auth::Authorization)::SpaceUsage
    res = post_rpc(auth, "users/get_space_usage")
    return SpaceUsage(res)
end

end
