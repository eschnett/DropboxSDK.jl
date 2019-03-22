#!/usr/bin/env julia

# Find path of this script
path = dirname(dirname(Base.PROGRAM_FILE))

# Activate the DropboxSDK package
using Pkg
Pkg.activate(path)

# Read the CLI commands
include(joinpath(path, "src", "DropboxCLI.jl"))

# Execute the command
exit_code = DropboxCLI.main(Base.ARGS)
exit(exit_code)
