using Dates
using Test
using UUIDs



const timestamp = Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sss")
const uuid = UUIDs.uuid4()
const folder = "test-$timestamp-$uuid"
println("Using folder \"$folder\" for testing")



#TODO include("testsdk.jl")
include("testcli.jl")
