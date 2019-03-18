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
        lines = runcmd(`put $filename $folder/hello2`)
        @test length(lines) == 0
    end
end



@testset "Command ls" begin
    lines = runcmd(`ls $folder`)
    @test length(lines) == 2
    @test lines[1] == "hello"
    @test lines[2] == "hello2"
end



@testset "Command get" begin
    mktempdir() do dir
        lines = runcmd(`get $folder/hello $dir`)
        @show lines
        @test length(lines) == 0
        content = read(joinpath(dir, "hello"))
        @show content
        @test String(content) == "Hello, World!\n"
        lines = runcmd(`get $folder/hello2 $(joinpath(dir, "hello2"))`)
        @show lines
        @test length(lines) == 0
        content = read(joinpath(dir, "hello2"))
        @show content
        @test String(content) == "Hello, World!\n"
    end
end



@testset "Command rm" begin
    lines = runcmd(`rm $folder`)
    @test length(lines) == 0
end
