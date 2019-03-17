module DropboxCLI

using ArgParse

using DropboxSDK



const arg_settings = ArgParseSettings()

add_arg_table(
    arg_settings,
    "account", Dict(:help => "show account information",
                    :action => :command),
    "du", Dict(:help => "show disk usage",
               :action => :command),
    "get", Dict(:help => "get files or directories",
                :action => :command),
    "ls", Dict(:help => "list directory content",
               :action => :command),
    "mkdir", Dict(:help => "create new directory",
                  :action => :command),
    "put", Dict(:help => "put files or directories",
                :action => :command),
    "rm", Dict(:help => "delete file or directory",
               :action => :command),
    "version", Dict(:help => "delete file or directory",
                    :action => :command),
)

add_arg_table(
    arg_settings["get"],
    "filename", Dict(:help => "name of Dropbox file or directory to get",
                     :nargs => '*'),
    "destination", Dict(:help => "local destination file or directory",
                        :nargs => 'A'),
)

add_arg_table(
    arg_settings["ls"],
    ["--long", "-l"], Dict(:help => "use a long (detailed) format",
                           :nargs => 0),
    ["--recursive", "-R"], Dict(:help => "recursively list subdirectories",
                                :nargs => 0),
    "filename", Dict(:help => "file or directory name",
                     :nargs => '*'),
)

add_arg_table(
    arg_settings["mkdir"],
    "directoryname", Dict(:help => "name of directory to create",
                       :nargs => '*'),
)

add_arg_table(
    arg_settings["put"],
    "filename", Dict(:help => "name of local file or directory to put",
                     :nargs => '*'),
    "destination", Dict(:help => "destination Dropbox file or directory",
                        :nargs => 'A'),
)

add_arg_table(
    arg_settings["rm"],
    "filename", Dict(:help => "name of file or directory to remove",
                     :nargs => '*'),
    ["--recursive", "-r"], Dict(:help => "recursively delete subdirectories",
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

function quote_string1(str::AbstractString)::String
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

function quote_string(str::AbstractString)::AbstractString
    repr(str)[2:end-1]
end



function cmd_account(args)
    auth = get_authorization()
    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    println("Account: Name: $first $last ($display)")
end



const metric_prefixes = ["", "k", "M", "G", "T", "P", "E", "Z", "Y"]
function find_prefix(x::Real)::Tuple{Int64, String}
    for (exp3, prefix) in enumerate(metric_prefixes)
        scale = 1000.0^(exp3-1)
        if abs(x) < 1000.0*scale
            return scale, prefix
        end
    end
    return 1, ""
end

function cmd_du(args)
    auth = get_authorization()
    usage::SpaceUsage = users_get_space_usage(auth)
    used = usage.used
    allocated = usage.allocation.allocated

    max_bytes = max(used, allocated)
    bytes_digits = length(string(max_bytes))

    scale, prefix = find_prefix(allocated)
    println("allocated:",
            " $(lpad(allocated, bytes_digits)) bytes",
            " ($(round(allocated / scale, sigdigits=3)) $(prefix)Byte)")

    scale, prefix = find_prefix(used)
    pct = round(100 * used / allocated, digits=1)
    println("used:     ",
            " $(lpad(used, bytes_digits)) bytes",
            " ($(round(used / scale, sigdigits=3)) $(prefix)Byte, $pct%)")
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

        # Distinguish between files and directories
        if source == ""
            # The root directory does not support files_get_metadata
            isdir_source = true
        else
            metadata = files_get_metadata(auth, source)
            if metadata isa Error
                println("$(quote_string(source)):",
                        " $(metadata.dict["error_summary"])")
                continue
            end
            isdir_source = metadata isa FolderMetadata
        end

        if isdir(destination)
            # If the destination is a directory, the files will be
            # downloaded into that directory.
            filename = joinpath(destination, basename(source))
        elseif length(sources) == 1 && !isdir_source
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

        # TODO: Handle sources that are a directory
        @assert !isdir_source

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

        # TODO: touch file if download is skipped?
        if need_download
            # TODO: download all files simultaneously
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
    # Directories prefixed with their names. Also sort everything
    # alphabetically.
    for filename in filenames

        # Add leading and remove trailing slashes
        if !startswith(filename, "/")
            filename = "/$filename"
        end
        while endswith(filename, "/")
            filename = filename[1:end-1]
        end

        # Distinguish between files and directories
        if filename == ""
            # The root directory does not support files_get_metadata
            isdirectory = true
        else
            metadata = files_get_metadata(auth, filename)
            if metadata isa Error
                println("$(quote_string(filename)):",
                        " $(metadata.dict["error_summary"])")
                continue
            end
            isdirectory = metadata isa FolderMetadata
        end

        if isdirectory
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
                isdir = metadata isa FolderMetadata
                mode = mode_strings[typeof(metadata)]
                size = isdir ? "" : metadata_size(metadata)
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
    directorynames = args["directoryname"]

    auth = get_authorization()
    for directoryname in directorynames

        # Add leading and remove trailing slashes
        if !startswith(directoryname, "/")
            directoryname = "/" * directoryname
        end
        while endswith(directoryname, "/")
            directoryname = directoryname[1:end-1]
        end

        res = files_create_folder(auth, directoryname)
        if res isa Error
            println("$(quote_string(directoryname)):",
                    " $(res.dict["error_summary"])")
        end

    end
end



function cmd_put(args)
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

    # Add leading and remove trailing slashes
    if !startswith(destination, "/")
        destination = "/$destination"
    end
    while endswith(destination, "/")
        destination = destination[1:end-1]
    end

    if destination == ""
        # The root directory does not support files_get_metadata
        ispath_destination = true
        isdir_destination = true
    else
        metadata = files_get_metadata(auth, destination)
        if metadata isa Error
            if metadata.dict["error"][".tag"] == "path" &&
                metadata.dict["error"]["path"][".tag"] == "not_found"
                ispath_destination = false
                isdir_destination = false
            else
                println("$(quote_string(destination)):",
                        " $(metadata.dict["error_summary"])")
                exit(1)
            end
        end
        ispath_destination = true
        isdir_destination = metadata isa FolderMetadata
    end

    for source in sources

        # Distinguish between files and directories
        if !ispath(source)
            println("$source: File not found")
            continue
        end
        isdir_source = isdir(source)

        if isdir_destination
            # If the destination is a directory, the files will be
            # downloaded into that directory.
            filename = joinpath(destination, basename(source))
        elseif length(sources) == 1 && !isdir_source
            # If there is only a single source
            if ispath_destination
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

        # Add leading and remove trailing slashes
        if !startswith(filename, "/")
            filename = "/$filename"
        end
        while endswith(filename, "/")
            filename = filename[1:end-1]
        end

        # TODO: Handle sources that are a directory
        @assert !isdir_source

        # Compare content hash before uploading
        need_upload = true
        content = nothing
        metadata = files_get_metadata(auth, filename)
        if metadata isa FileMetadata
            size = filesize(source)
            if metadata.size == size
                # Don't upload if content hash matches
                content = read(source)
                content_hash = calc_content_hash(content)
                if metadata.content_hash == content_hash
                    @show "content hash matches; skipping upload"
                    need_upload = false
                end
            elseif metadata.size < size
                # TODO: Upload only missing fraction
            end
        end

        # TODO: touch Dropbox file if upload is skipped?
        if need_upload
            if content === nothing
                content = read(source)
            end
            # TODO: upload all files simultaneously
            metadata = files_upload(auth, filename, content)
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



const re_name_to_string    = r"^\s*name\s*=\s*\"(.*)\"\s*(?:#|$)"
const re_version_to_string = r"^\s*version\s*=\s*\"(.*)\"\s*(?:#|$)"

function cmd_version(args)
    project_filename = joinpath(dirname(dirname(pathof(DropboxSDK))),
                                "Project.toml")
    name = nothing
    version = nothing
    open(project_filename) do io
        for line in eachline(io)
            if (m = match(re_name_to_string, line)) != nothing
                name = String(m.captures[1])
            elseif (m = match(re_version_to_string, line)) != nothing
                version = VersionNumber(m.captures[1])
            end
        end
    end
    @assert name == "DropboxSDK"

    println("Version $version")
end



const cmds = Dict(
    "account" => cmd_account,
    "du" => cmd_du,
    "get" => cmd_get,
    "ls" => cmd_ls,
    "mkdir" => cmd_mkdir,
    "put" => cmd_put,
    "rm" => cmd_rm,
    "version" => cmd_version,
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

end
