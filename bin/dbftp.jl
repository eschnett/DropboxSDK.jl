#!/usr/bin/env julia

# Find path of this script
path = abspath(dirname(Base.PROGRAM_FILE), "..")

# # Activate the DropboxSDK package
# using Pkg
# Pkg.activate(path)
# 
# # Read the CLI commands
# include(joinpath(path, "src", "DropboxCLI.jl"))

using DropboxSDK

# Execute the command
exit_code = DropboxSDK.DropboxCLI.main(Base.ARGS)
exit(exit_code)
