function quote_string(str::AbstractString)::AbstractString
    repr(str)[2:end-1]
end



function runcmd(args::Cmd; wrap=identity)::Vector{String}
    julia = Base.julia_cmd()
    dbftp = joinpath("..", "bin", "dbftp")
    lines = String[]
    open(wrap(`$julia $dbftp $args`)) do io
        skipcount = 0
        for line in eachline(io)
            if skipcount > 0
                skipcount -= 1
                continue
            elseif startswith(line, "Julia Dropbox client")
                skipcount = 1
                continue
            elseif startswith(line, "Info: ") || startswith(line, "\rInfo: ")
                continue
            else
                push!(lines, line)
            end
        end
    end
    lines
end



@testset "Command version" begin
    lines = runcmd(`version`)
    @test length(lines) == 1
    m = match(r"^Version\s+(.*)", lines[1])
    @test m !== nothing
    version = VersionNumber(m.captures[1])
end



@testset "Command account" begin
    lines = runcmd(`account`)
    @test length(lines) == 1
    m = match(r"^Account: Name:\s+", lines[1])
    @test m !== nothing
end



@testset "Command du" begin
    lines = runcmd(`du`)
    @test length(lines) == 2
    m = match(r"^allocated:\s+(.*)", lines[1])
    @test m !== nothing
    m = match(r"^used:\s+(.*)", lines[2])
    @test m !== nothing
end



@testset "Command mkdir" begin
    lines = runcmd(`mkdir $folder`)
    @test length(lines) == 0
end



@testset "Command put" begin
    mktempdir() do dir
        filename = joinpath(dir, "hello")
        content = Vector{UInt8}("Hello, World!\n")
        write(filename, content)
        lines = runcmd(`put $filename $folder`)
        @test length(lines) == 0

        lines = runcmd(`put $filename $folder/hello`)
        @test length(lines) == 0

        filename2 = joinpath(dir, "hello2")
        content2 = Vector{UInt8}("Hello, World 2!\n")
        write(filename2, content2)
        lines = runcmd(`put $filename2 $folder/hello2`)
        @test length(lines) == 0

        dirname = joinpath(dir, "dir")
        mkdir(dirname)
        filename3 = joinpath(dirname, "hello3")
        content3 = Vector{UInt8}("Hello, World 3!\n")
        write(filename3, content3)
        lines = runcmd(`put $dirname $folder`)
        @test length(lines) == 0
    end
end



@testset "Command cmp" begin
    mktempdir() do dir
        filename = joinpath(dir, "hello")
        content = Vector{UInt8}("Hello, World!\n")
        write(filename, content)
        lines = runcmd(`cmp $filename $folder`)
        @test length(lines) == 0

        lines = runcmd(`cmp $filename $folder/hello`)
        @test length(lines) == 0

        lines = runcmd(`cmp $filename $folder/hello2`; wrap=ignorestatus)
        @test length(lines) == 1
        quoted_filename = quote_string(filename)
        @test lines[1] == "$quoted_filename: File size differs"

        filename2 = joinpath(dir, "hello2")
        content2 = Vector{UInt8}("Hello, World 2!\n")
        write(filename2, content2)
        lines = runcmd(`cmp $filename2 $folder/hello2`)
        @test length(lines) == 0

        # TODO: compare recursively
        dirname = joinpath(dir, "dir")
        mkdir(dirname)
        filename3 = joinpath(dirname, "hello3")
        content3 = Vector{UInt8}("Hello, World 3!\n")
        write(filename3, content3)
        lines = runcmd(`cmp $filename3 $folder/dir/hello3`)
        @test length(lines) == 0
    end
end



@testset "Command ls" begin
    lines = runcmd(`ls $folder`)
    @test length(lines) == 3
    @test lines[1] == "dir"
    @test lines[2] == "hello"
    @test lines[3] == "hello2"

    lines = runcmd(`ls -l $folder`)
    @test length(lines) == 3
    @test startswith(lines[1], "d    ")
    @test startswith(lines[2], "- 14 ")
    @test startswith(lines[3], "- 16 ")
    @test endswith(lines[1], " dir")
    @test endswith(lines[2], " hello")
    @test endswith(lines[3], " hello2")
end



@testset "Command get" begin
    mktempdir() do dir
        filename = joinpath(dir, "hello")
        lines = runcmd(`get $folder/hello $dir`)
        @test length(lines) == 0
        content = read(filename)
        @test String(content) == "Hello, World!\n"

        lines = runcmd(`get $folder/hello $filename`)
        @test length(lines) == 0
        content = read(joinpath(dir, "hello"))
        @test String(content) == "Hello, World!\n"

        filename2 = joinpath(dir, "hello2")
        lines = runcmd(`get $folder/hello2 $filename2`)
        @test length(lines) == 0
        content2 = read(filename2)
        @test String(content2) == "Hello, World 2!\n"

        # TODO: download recursively
        dirname = joinpath(dir, "dir")
        mkdir(dirname)
        filename3 = joinpath(dirname, "hello3")
        content3 = Vector{UInt8}("Hello, World 3!\n")
        lines = runcmd(`get $folder/dir/hello3 $filename3`)
        @test length(lines) == 0
        content3 = read(filename3)
        @test String(content3) == "Hello, World 3!\n"
    end
end



@testset "Command rm" begin
    lines = runcmd(`rm $folder`)
    @test length(lines) == 0
end
