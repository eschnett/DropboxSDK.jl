using DropboxSDK



filename(entry) =
    entry.path_display === nothing ? entry.name : entry.path_display



@testset "Get authorization" begin
    global auth = get_authorization()
    @test auth isa Authorization
end

@testset "Calculate content hash" begin
    content = read(joinpath("..", "data", "ssc2006-02a1_Lrg.jpg"))
    @assert length(content) == 6056980
    content_hash = calc_content_hash(content)
    @test (content_hash ==
           "8a6ebea6983dc68be1575676d3a8ec0d664cfee69b2dbcdf44087cf5d455fe12")

    len = length(content)
    di = 1234567
    contents = []
    for i in 1:di:len
        push!(contents, @view content[i : min(len, i + di - 1)])
    end
    @assert sum(length.(contents)) == length(content)
    # @assert vcat(contents...) == content

    data_channel, content_hash_channel = calc_content_hash_start()
    for content in contents
        put!(data_channel, content)
    end
    close(data_channel)
    content_hash = take!(content_hash_channel)
    @test (content_hash ==
           "8a6ebea6983dc68be1575676d3a8ec0d664cfee69b2dbcdf44087cf5d455fe12")
end



@testset "Get current account" begin
    account = users_get_current_account(auth)
    first = account.name.given_name
    last = account.name.surname
    display = account.name.display_name
    @test first == "Erik"
    @test last == "Schnetter"
    @test display == "Erik Schnetter (PI)"
end

@testset "Get space usage" begin
    usage = users_get_space_usage(auth)
    used = usage.used
    @test used isa Integer
    @test used >= 0
end

@testset "List folder" begin
    entries = files_list_folder(auth, "", recursive=true)
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

# @testset "Upload file in chunks" begin
#     content = map(Vector{UInt8}, ["Hello, ","World!\n"])
#     metadata = files_upload(auth, "/$folder/file1", ContentIterator(content))
#     @test metadata isa FileMetadata
#     @test metadata.size == length("Hello, World!\n")
#     entries = files_list_folder(auth, "/$folder", recursive=true)
#     @test count(entry -> startswith(entry.path_display, "/$folder"),
#                 entries) == 4
#     @test count(entry -> entry.path_display == "/$folder", entries) == 1
#     @test count(entry -> entry.path_display == "/$folder/file1", entries) == 1
# end

@testset "Upload file in chunks" begin
    upload_channel, metadata_channel =
        files_upload_start(auth, "/$folder/file1")
    put!(upload_channel, Vector{UInt8}("Hello, "))
    put!(upload_channel, Vector{UInt8}("World!\n"))
    close(upload_channel)
    metadata = take!(metadata_channel)
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

# @testset "Upload empty file in chunks" begin
#     content = map(Vector{UInt8}, String[])
#     metadata = files_upload(auth, "/$folder/file2", ContentIterator(content))
#     @test metadata isa FileMetadata
#     @test metadata.size == 0
#     entries = files_list_folder(auth, "/$folder", recursive=true)
#     @test count(entry -> startswith(entry.path_display, "/$folder"),
#                 entries) == 5
#     @test count(entry -> entry.path_display == "/$folder", entries) == 1
#     @test count(entry -> entry.path_display == "/$folder/file2", entries) == 1
# end

@testset "Upload empty file in chunks" begin
    upload_channel, metadata_channel =
        files_upload_start(auth, "/$folder/file2")
    close(upload_channel)
    metadata = take!(metadata_channel)
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
# @testset "Upload several files" begin
#     chunk = Vector{UInt8}("Hello, World!\n")
#     contents = StatefulIterator{Tuple{String, ContentIterator}}(
#         ("/$folder/files$i", ContentIterator(Iterators.repeated(chunk, i)))
#         for i in 0:numfiles-1)
#     metadatas = files_upload(auth, contents)
#     @test length(metadatas) == numfiles
#     @test all(metadata isa FileMetadata for metadata in metadatas)
#     @test all(metadata.size == (i-1) * length("Hello, World!\n")
#               for (i,metadata) in enumerate(metadatas))
#     entries = files_list_folder(auth, "/$folder", recursive=true)
#     @test count(entry -> startswith(entry.path_display, "/$folder"),
#                 entries) == numfiles + 5
#     @test count(entry -> entry.path_display == "/$folder", entries) == 1
#     for i in 0:numfiles-1
#         @test count(entry -> entry.path_display == "/$folder/files$i",
#                     entries) == 1
#     end
# end

@testset "Upload several files" begin
    upload_spec_channel, metadatas_channel = files_upload_start(auth)
    for i in 0:numfiles-1
        data_channel = Channel{Vector{UInt8}}(0)
        put!(upload_spec_channel,
             UploadSpec(data_channel, "/$folder/files$i"))
        for j in 1:i
            put!(data_channel, Vector{UInt8}("Hello, World!\n"))
        end
        close(data_channel)
    end
    close(upload_spec_channel)
    metadatas = take!(metadatas_channel)
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

# @testset "Upload zero files" begin
#     contents = StatefulIterator{Tuple{String, ContentIterator}}(
#         Tuple{String, ContentIterator}[]
#     )
#     metadatas = files_upload(auth, contents)
#     @test isempty(metadatas)
#     entries = files_list_folder(auth, "/$folder", recursive=true)
#     @test count(entry -> startswith(entry.path_display, "/$folder"),
#                 entries) == numfiles + 5
# end

@testset "Upload zero files" begin
    upload_spec_channel, metadatas_channel = files_upload_start(auth)
    close(upload_spec_channel)
    metadatas = take!(metadatas_channel)
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
