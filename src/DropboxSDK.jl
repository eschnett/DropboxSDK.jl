module DropboxSDK

using ConfParser
using HTTP
using JSON



struct Nothing2 end
const nothing2 = Nothing2()
function mapget(fun::Function, dict::Dict, key, default=nothing)
    value = get(dict, key, nothing2)
    if value === nothing2 return default end
    fun(value)
end



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
    args = Dict(
        "path" => path,
        "recursive" => false,
        "include_media_info" => false,
        "include_deleted" => false,
        "include_has_explicit_shared_members" => false,
        "include_mounted_folders" => true,
    )
    resp = HTTP.request(
        "POST",
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
    Union{Nothing, FullAccount}
    resp = HTTP.request(
        "POST",
        "https://api.dropboxapi.com/2/users/get_current_account",
        ["Authorization" => "Bearer $(auth.access_token)",
         ],
        verbose=0)
    if ! (200 <= resp.status <= 299)
        println("Error:")
        println("Status: $(resp.status)")
        println(String(resp.body))
        return nothing
    end
    res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
    FullAccount(res)
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

SpaceUsage(d::Dict) = SpaceUsage(
    d["used"],
    d["allocation"],
)

function users_get_space_usage(auth::Authorization)::
    Union{Nothing, SpaceUsage}
    resp = HTTP.request(
        "POST",
        "https://api.dropboxapi.com/2/users/get_space_usage",
        ["Authorization" => "Bearer $(auth.access_token)",
         ],
        verbose=0)
    if ! (200 <= resp.status <= 299)
        println("Error:")
        println("Status: $(resp.status)")
        println(String(resp.body))
        return nothing
    end
    res = JSON.parse(String(resp.body); dicttype=Dict, inttype=Int64)
    SpaceUsage(res)
end



function main()
    auth = read_authorization()

    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    println("account: name: $first $last ($display)")

    usage = users_get_space_usage(auth)
    used = usage.used
    println("usage: $(round(Int, used / 1.0e9)) GByte")

    files = files_list_folder(auth, "")
    println("files:")
    for (i,file) in enumerate(files)
        println("$i: $file")
    end
end

end
