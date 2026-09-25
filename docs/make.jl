# Inside make.jl
push!(LOAD_PATH,"../src/")
include("../Lib/functions.jl")
import .func
using Documenter

makedocs(
         sitename = "PipingTool.jl",
         modules  = [func],
         pages=[
                "Home" => "index.md",
                "Documentation" => "documentation.md",
                "Example" => "example.md",
                "Licence" => "licence.md"
               ]
        )
deploydocs(;
    repo="https://github.com/polymtl-bee/PipingTool",
          )