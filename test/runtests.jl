using Dates
using Test
using UUIDs



# Avoid colons in the timestamp
const timestamp = Dates.format(now(UTC), dateformat"yyyy-mm-dd-HH-MM-SS.sss")
const uuid = UUIDs.uuid4()
const folder = "test-$timestamp-$uuid"
println("Using folder \"$folder\" for testing")



include("testsdk.jl")
include("testcli.jl")
