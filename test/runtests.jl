using Test
using UUIDs

using DropboxSDK


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

const folder = "test-$(UUIDs.uuid4())"
filename(entry) =
    entry.path_display === nothing ? entry.name : entry.path_display

@testset "List folder" begin
    entries = files_list_folder(auth, "", recursive=true)
    # for (i,entry) in enumerate(entries)
    #     println("    $i: $(filename(entry))")
    # end
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 0
end

@testset "Create folder" begin
    files_create_folder(auth, "/$folder")
    entries = files_list_folder(auth, "", recursive=true)
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 1
    @test count(entry -> filename(entry) == "/$folder", entries) == 1
end

@testset "Upload file" begin
    files_upload(auth, "/$folder/file", Vector{UInt8}("Hello, World!\n"))
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 2
    @test count(entry -> filename(entry) == "/$folder", entries) == 1
    @test count(entry -> filename(entry) == "/$folder/file", entries) == 1
end

@testset "Download file" begin
    metadata, content = files_download(auth, "/$folder/file")
    @test filename(metadata) == "/$folder/file"
    @test String(content) == "Hello, World!\n"
end

@testset "Upload empty file" begin
    files_upload(auth, "/$folder/file0", Vector{UInt8}(""))
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 3
    @test count(entry -> filename(entry) == "/$folder", entries) == 1
    @test count(entry -> filename(entry) == "/$folder/file0", entries) == 1
end

@testset "Download empty file" begin
    metadata, content = files_download(auth, "/$folder/file0")
    @test filename(metadata) == "/$folder/file0"
    @test String(content) == ""
end

@testset "Upload file via session" begin
    content = map(Vector{UInt8}, ["Hello, ","World!\n"])
    files_upload(auth, "/$folder/file1", Iterators.Stateful(content))
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 4
    @test count(entry -> filename(entry) == "/$folder", entries) == 1
    @test count(entry -> filename(entry) == "/$folder/file1", entries) == 1
end

@testset "Download file" begin
    metadata, content = files_download(auth, "/$folder/file1")
    @test filename(metadata) == "/$folder/file1"
    @test String(content) == "Hello, World!\n"
end

@testset "Upload empty file via session" begin
    content = map(Vector{UInt8}, ["Hello, ","World!\n"])
    files_upload(auth, "/$folder/file2", Iterators.Stateful(content))
    entries = files_list_folder(auth, "/$folder", recursive=true)
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 5
    @test count(entry -> filename(entry) == "/$folder", entries) == 1
    @test count(entry -> filename(entry) == "/$folder/file2", entries) == 1
end

@testset "Download empty file" begin
    metadata, content = files_download(auth, "/$folder/file2")
    @test filename(metadata) == "/$folder/file2"
    @test String(content) == "Hello, World!\n"
end

@testset "Delete folder" begin
    files_delete(auth, "/$folder")
    entries = files_list_folder(auth, "", recursive=true)
    @test count(entry -> startswith(filename(entry), "/$folder"), entries) == 0
end
