using Pkg
Pkg.activate(".")

using ArgParse

using DropboxSDK



const arg_settings = ArgParseSettings()

add_arg_table(
    arg_settings,
    "account", Dict(:help => "show account information",
                    :action => :command),
    "ls", Dict(:help => "list folder content",
               :action => :command),
)

add_arg_table(
    arg_settings["ls"],
    ["--long", "-l"], Dict(:help => "Use a long (detailed) format",
                           :nargs => 0),
    ["--recursive", "-R"], Dict(:help => "Recursively list subfolders",
                                :nargs => 0),
)

parse_commandline() = parse_args(arg_settings)



function cmd_account(args)
    auth = get_authorization()
    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    println("    Account: Name: $first $last ($display)")
end



function cmd_ls(args)
    long = args["long"]
    recursive = args["recursive"]
    auth = get_authorization()
    entries = files_list_folder(auth, "", recursive=recursive)
    for entry in entries
        println("    $(entry.path_display)")
    end
end



const cmds = Dict(
    "account" => cmd_account,
    "ls" => cmd_ls,
)



function main()
    println("Julia Dropbox client   ",
            "<https://github.com/eschnett/DropboxSDK.jl>")
    args = parse_commandline()
    cmd = args["%COMMAND%"]
    fun = cmds[cmd]
    fun(args[cmd])
end

main()
