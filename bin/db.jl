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
    "mkdir", Dict(:help => "create new folder",
                  :action => :command),
)

add_arg_table(
    arg_settings["ls"],
    ["--long", "-l"], Dict(:help => "Use a long (detailed) format",
                           :nargs => 0),
    ["--recursive", "-R"], Dict(:help => "Recursively list subfolders",
                                :nargs => 0),
    "filename", Dict(:help => "file name",
                     :nargs => '*'),
)



const escape_char = Dict{Char, Char}(
    ' ' => ' ',
    '"' => '"',
    '\'' => '\'',
    '\\' => '\\',
    '\a' => 'a',
    '\b' => 'b',
    '\e' => 'e',
    '\f' => 'f',
    '\n' => 'n',
    '\r' => 'r',
    '\t' => 't',
    '\v' => 'v',
)

function quote_string(str::String)::String
    buf = IOBuffer()
    for c in str
        if isprint(c) && c != ' '
            print(buf, c)
        else
            ec = get(escape_char, c, '#')
            if ec != '#'
                print(buf, '\\', escape_char[c])
            else
                i = UInt(c)
                if i <= 0xff
                    print(buf, "\\x", lpad(string(i), 2, '0'))
                elseif i <= 0xffff
                    print(buf, "\\u", lpad(string(i), 4, '0'))
                else
                    print(buf, "\\U", lpad(string(i), 8, '0'))
                end
            end
        end
    end
    String(take!(buf))
end



function cmd_account(args)
    auth = get_authorization()
    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    println("Account: Name: $first $last ($display)")
end



const mode_strings = Dict{Type, String}(
    FileMetadata => "-",
    FolderMetadata => "d",
    DeletedMetadata => "?",
)

metadata_size(metadata) = Int64(0)
metadata_size(metadata::FileMetadata) = metadata.size

# e.g. "2019-03-15T23:05:18Z"))
metadata_modified(metadata) = "                    " # 20 spaces
metadata_modified(metadata::FileMetadata) = metadata.server_modified

function metadata_path(metadata, prefix)
    path = metadata.path_display
    if startswith(path, prefix)
        path = path[length(prefix)+1 : end]
    end
    if startswith(path, "/")
        path = path[2:end]
    end
    path
end

function cmd_ls(args)
    long = args["long"]
    recursive = args["recursive"]
    filenames = args["filename"]
    if isempty(filenames)
        filenames = [""]        # show root
    end

    auth = get_authorization()
    for filename in filenames

        # Add leading and remove trailing slashes
        if !startswith(filename, "/")
            filename = "/" * filename
        end
        while endswith(filename, "/")
            filename = filename[1:end-1]
        end

        # Distinguish between files and folders
        metadata = files_get_metadata(auth, filename)
        if metadata isa Error
            println("$(quote_string(isempty(filename) ? "/" : filename)):",
                    " no such file or directory")
            continue
        elseif metadata isa FolderMetadata
            metadatas = files_list_folder(auth, filename, recursive=recursive)
        else
            metadatas = [metadata]
        end

        # Output directory name if there are multiple directories
        if metadata isa FolderMetadata && length(filenames) > 1
            println()
            println("$(quote_string(isempty(filename) ? "/" : filename)):")
        end

        # Output
        if long
            max_size = maximum(metadata_size(metadata)
                               for metadata in metadatas)
            size_digits = length(string(max_size))
            for metadata in metadatas
                mode = mode_strings[typeof(metadata)]
                size = metadata_size(metadata)
                modified = metadata_modified(metadata)
                path = metadata_path(metadata, filename)
                println("$mode $(lpad(size, size_digits)) $modified",
                        " $(quote_string(path))")
            end
        else
            for metadata in metadatas
                path = metadata_path(metadata, filename)
                println("$(quote_string(path))")
            end
        end
        
    end
end



const cmds = Dict(
    "account" => cmd_account,
    "ls" => cmd_ls,
)



function main(args)
    println("Julia Dropbox client   ",
            "<https://github.com/eschnett/DropboxSDK.jl>")
    println()
    opts = parse_args(args, arg_settings)
    cmd = opts["%COMMAND%"]
    fun = cmds[cmd]
    fun(opts[cmd])
end

main(Base.ARGS)
