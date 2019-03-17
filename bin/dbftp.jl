using Pkg
Pkg.activate(".")

include("../src/DropboxCLI.jl")

DropboxCLI.main(Base.ARGS)
