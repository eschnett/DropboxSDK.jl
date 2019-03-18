using Pkg
Pkg.activate(".")

include("../src/DropboxCLI.jl")

exit_code = DropboxCLI.main(Base.ARGS)
exit(exit_code)
