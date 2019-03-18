using Pkg
Pkg.activate(".")

include("../src/DropboxCLI.jl")

code = DropboxCLI.main(Base.ARGS)
exit(code)
