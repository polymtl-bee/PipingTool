# Inside make.jl
push!(LOAD_PATH,"../src/")
include("../src/PipingTool.jl")
import .PipingTool
using CSV, DataFrames, NonlinearSolve, PrettyTables, Printf, Statistics, Unitful, DataStructures, OrderedCollections, PlotlyJS, GraphPlot, Graphs, Compose, Cairo, Fontconfig
using Documenter

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