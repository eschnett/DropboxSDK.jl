using Pkg
Pkg.activate(".")

using ArgParse

using DropboxSDK



const arg_settings = ArgParseSettings()

add_arg_table(
    arg_settings,
    "account", Dict(:help => "show account information",
                    :action => :command),
    "get", Dict(:help => "get files or folders",
                :action => :command),
    "ls", Dict(:help => "list folder content",
               :action => :command),
    "mkdir", Dict(:help => "create new folder",
                  :action => :command),
    "rm", Dict(:help => "delete file or folder",
               :action => :command),
)

add_arg_table(
    arg_settings["get"],
    "filename", Dict(:help => "name of file or folder in Dropbox to get",
                     :nargs => '*'),
    "destination", Dict(:help => "local destination file or folder",
                        :nargs => 'A'),
)

add_arg_table(
    arg_settings["ls"],
    ["--long", "-l"], Dict(:help => "use a long (detailed) format",
                           :nargs => 0),
    ["--recursive", "-R"], Dict(:help => "recursively list subfolders",
                                :nargs => 0),
    "filename", Dict(:help => "file or folder name",
                     :nargs => '*'),
)

add_arg_table(
    arg_settings["mkdir"],
    "foldername", Dict(:help => "name of folder to create",
                       :nargs => '*'),
)

add_arg_table(
    arg_settings["rm"],
    "filename", Dict(:help => "name of file or folder to remove",
                     :nargs => '*'),
    ["--recursive", "-r"], Dict(:help => "recursively delete subfolders",
                                :nargs => 0),
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



function cmd_get(args)
    filenames = args["filename"]
    if length(filenames) == 0
        println("Error: No file names given")
        exit(1)
    elseif length(filenames) == 1
        println("Error: Destination missing")
        exit(1)
    end
    # The last file name is the destination
    @assert !haskey(args, "target")
    destination = filenames[end]
    sources = filenames[1:end-1]

    auth = get_authorization()

    for source in sources

        # Add leading and remove trailing slashes
        if !startswith(source, "/")
            source = "/$source"
        end
        @assert !endswith(source, "/")

        # Distinguish between files and folders
        if source == ""
            # The root folder does not support files_get_metadata
            isfolder = true
        else
            metadata = files_get_metadata(auth, source)
            if metadata isa Error
                println("$(quote_string(filename)):",
                        " $(metadata.dict["error_summary"])")
                continue
            end
            isfolder = metadata isa FolderMetadata
        end
        # TODO: Handle sources that are a folder
        @assert !isfolder

        if isdir(destination)
            # If the destination is a directory, the files will be
            # downloaded into that directory.
            filename = joinpath(destination, basename(source))
        elseif length(sources) == 1
            # If there is only a single source
            if ispath(destination)
                # If the destination exists and is not a directory,
                # then it is overwritten.
                @assert !isdirpath(destination)
                filename = destination
            else
                # If the destination does not exist, then a file with
                # that name will be created.
                filename = destination
                pathname = dirname(filename)
                @assert isdir(pathname)
            end
        else
            # Multiple sources: Destination is not a directory
            @assert false
        end

        # Compare content hash before downloading
        need_download = true
        if metadata.size == 0
            open(destination, "w") do io
                truncate(io, 0)
            end
            need_download = false
        elseif isfile(destination)
            size = filesize(destination)
            if size == metadata.size
                # Don't download if content hash matches
                content = read(destination)
                content_hash = calc_content_hash(content)
                if content_hash == metadata.content_hash
                    @show "content hash matches; skipping download"
                    need_download = false
                end
            elseif size < metadata.size
                # TODO: Download only missing fraction
            else
                # Truncate if necessary
                content = read(destination, metadata.size)
                content_hash = calc_content_hash(content)
                if content_hash == metadata.content_hash
                    @show "content hash matches; truncating local file and skipping download"
                    open(destination, "w") do io
                        truncate(io, metadata.size)
                    end
                    need_download = false
                end
            end
        end

        if need_download
            metadata, content = files_download(auth, source)
            open(destination, "w") do io
                write(io, content)
            end
        end

    end
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
    if path == ""
        path = "."
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

    # TODO: Sort filenames by type. First show all Files, then all
    # Folders prefixed with their names. Also sort everything
    # alphabetically.
    for filename in filenames

        # Add leading and remove trailing slashes
        if !startswith(filename, "/")
            filename = "/$filename"
        end
        while endswith(filename, "/")
            filename = filename[1:end-1]
        end

        # Distinguish between files and folders
        if filename == ""
            # The root folder does not support files_get_metadata
            isfolder = true
        else
            metadata = files_get_metadata(auth, filename)
            if metadata isa Error
                println("$(quote_string(filename)):",
                        " $(metadata.dict["error_summary"])")
                continue
            end
            isfolder = metadata isa FolderMetadata
        end

        if isfolder
            metadatas = files_list_folder(auth, filename, recursive=recursive)
            prefix_to_hide = filename
        else
            metadatas = [metadata]
            prefix_to_hide = ""
        end

        # Output directory name if there are multiple directories
        if length(filenames) > 1
            println()
            println("$(quote_string(filename)):")
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
                path = metadata_path(metadata, prefix_to_hide)
                println("$mode $(lpad(size, size_digits)) $modified",
                        " $(quote_string(path))")
            end
        else
            for metadata in metadatas
                path = metadata_path(metadata, prefix_to_hide)
                println("$(quote_string(path))")
            end
        end
        
    end
end



function cmd_mkdir(args)
    foldernames = args["foldername"]

    auth = get_authorization()
    for foldername in foldernames

        # Add leading and remove trailing slashes
        if !startswith(foldername, "/")
            foldername = "/" * foldername
        end
        while endswith(foldername, "/")
            foldername = foldername[1:end-1]
        end

        res = files_create_folder(auth, foldername)
        if res isa Error
            println("$(quote_string(foldername)): $(res.dict["error_summary"])")
        end

    end
end



function cmd_rm(args)
    filenames = args["filename"]

    auth = get_authorization()
    for filename in filenames

        # Add leading and remove trailing slashes
        if !startswith(filename, "/")
            filename = "/" * filename
        end
        while endswith(filename, "/")
            filename = filename[1:end-1]
        end

        res = files_delete(auth, filename)
        if res isa Error
            println("$(quote_string(filename)): $(res.dict["error_summary"])")
        end

    end
end



const cmds = Dict(
    "account" => cmd_account,
    "get" => cmd_get,
    "ls" => cmd_ls,
    "mkdir" => cmd_mkdir,
    "rm" => cmd_rm,
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
