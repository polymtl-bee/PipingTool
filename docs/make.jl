# Inside make.jl
push!(LOAD_PATH,"../src/")
include("../src/PipingTool.jl")
import .PipingTool

makedocs(
         sitename = "PipingTool.jl",
         modules  = [PipingTool],
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