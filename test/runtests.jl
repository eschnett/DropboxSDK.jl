using Dates
using Test
using UUIDs

using DropboxSDK



const timestamp = Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sss")
const uuid = UUIDs.uuid4()
const folder = "test-$timestamp-$uuid"
println("Using folder \"$folder\" for testing")

filename(entry) =
    entry.path_display === nothing ? entry.name : entry.path_display



@testset "Get authorization" begin
    global auth = get_authorization()
    @test auth isa Authorization
end

@testset "Get current account" begin
    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    # println("    account: name: $first $last ($display)")
    @test first == "Erik"
    @test last == "Schnetter"
    @test display == "Erik Schnetter (PI)"
end

@testset "Get space usage" begin
    usage = users_get_space_usage(auth)
    used = usage.used
    # println("    usage: $(round(Int, used / 1.0e9)) GByte")
    @test used isa Integer
    @test used >= 0
end

@testset "List folder" begin
    entries = files_list_folder(auth, "", recursive=true)
    # for (i,entry) in enumerate(entries)
    #     println("    $i: $(filename(entry))")
    # end
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 0
end

@testset "Create folder" begin
    files_create_folder(auth, "/$folder")
    entries = files_list_folder(auth, "", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 1
    @test count(entry -> entry.path_display == "/$folder", entries) == 1
end

@testset "Upload file" begin
    metadata =
        files_upload(auth, "/$folder/file", Vector{UInt8}("Hello, World!\n"))
    @test metadata isa FileMetadata
    @test metadata.size == length("Hello, World!\n")
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 2
    @test count(entry -> entry.path_display == "/$folder", entries) == 1
    @test count(entry -> entry.path_display == "/$folder/file", entries) == 1
end

@testset "Download file" begin
    metadata, content = files_download(auth, "/$folder/file")
    @test metadata.path_display == "/$folder/file"
    @test String(content) == "Hello, World!\n"
end

@testset "Get file metadata" begin
    metadata = files_get_metadata(auth, "/$folder/file")
    @test metadata.path_display == "/$folder/file"
    @test (metadata.content_hash ==
           calc_content_hash(Vector{UInt8}("Hello, World!\n")))
end

@testset "Upload empty file" begin
    metadata = files_upload(auth, "/$folder/file0", Vector{UInt8}(""))
    @test metadata isa FileMetadata
    @test metadata.size == 0
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 3
    @test count(entry -> entry.path_display == "/$folder", entries) == 1
    @test count(entry -> entry.path_display == "/$folder/file0", entries) == 1
end

@testset "Download empty file" begin
    metadata, content = files_download(auth, "/$folder/file0")
    @test metadata.path_display == "/$folder/file0"
    @test String(content) == ""
end

@testset "Upload file in chunks" begin
    content = map(Vector{UInt8}, ["Hello, ","World!\n"])
    metadata = files_upload(auth, "/$folder/file1", ContentIterator(content))
    @test metadata isa FileMetadata
    @test metadata.size == length("Hello, World!\n")
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 4
    @test count(entry -> entry.path_display == "/$folder", entries) == 1
    @test count(entry -> entry.path_display == "/$folder/file1", entries) == 1
end

@testset "Download file" begin
    metadata, content = files_download(auth, "/$folder/file1")
    @test metadata.path_display == "/$folder/file1"
    @test String(content) == "Hello, World!\n"
end

@testset "Upload empty file in chunks" begin
    content = map(Vector{UInt8}, String[])
    metadata = files_upload(auth, "/$folder/file2", ContentIterator(content))
    @test metadata isa FileMetadata
    @test metadata.size == 0
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 5
    @test count(entry -> entry.path_display == "/$folder", entries) == 1
    @test count(entry -> entry.path_display == "/$folder/file2", entries) == 1
end

@testset "Download empty file" begin
    metadata, content = files_download(auth, "/$folder/file2")
    @test metadata.path_display == "/$folder/file2"
    @test String(content) == ""
end

const numfiles = 4
@testset "Upload several files" begin
    chunk = Vector{UInt8}("Hello, World!\n")
    contents = StatefulIterator{Tuple{String, ContentIterator}}(
        ("/$folder/files$i", ContentIterator(Iterators.repeated(chunk, i)))
        for i in 0:numfiles-1)
    metadatas = files_upload(auth, contents)
    @test length(metadatas) == numfiles
    @test all(metadata isa FileMetadata for metadata in metadatas)
    @test all(metadata.size == (i-1) * length("Hello, World!\n")
              for (i,metadata) in enumerate(metadatas))
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == numfiles + 5
    @test count(entry -> entry.path_display == "/$folder", entries) == 1
    for i in 0:numfiles-1
        @test count(entry -> entry.path_display == "/$folder/files$i",
                    entries) == 1
    end
end

@testset "Download files" begin
    for i in 0:numfiles-1
        metadata, content = files_download(auth, "/$folder/files$i")
        @test metadata.path_display == "/$folder/files$i"
        @test String(content) == repeat("Hello, World!\n", i)
    end
end

@testset "Upload zero files" begin
    contents = StatefulIterator{Tuple{String, ContentIterator}}(
        Tuple{String, ContentIterator}[]
    )
    metadatas = files_upload(auth, contents)
    @test isempty(metadatas)
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == numfiles + 5
end

@testset "Delete folder" begin
    files_delete(auth, "/$folder")
    entries = files_list_folder(auth, "", recursive=true)
    @test count(entry -> startswith(entry.path_display, "/$folder"),
                entries) == 0
end


function runcmd(args::Cmd)::Vector{String}
    julia = Base.julia_cmd()
    lines = String[]
    open(`$julia ../bin/dbftp.jl $args`) do io
        skipcount = 0
        for line in eachline(io)
            if skipcount > 0
                skipcount -= 1
                continue
            elseif startswith(line, "Julia Dropbox client")
                skipcount = 1
                continue
            else
                push!(lines, line)
            end
        end
    end
    lines
end



@testset "Commands" begin
    lines = runcmd(`version`)
    @test length(lines) == 1
    m = match(r"^Version\s+(.*)", lines[1])
    @test m !== nothing
    version = VersionNumber(m.captures[1])
end
