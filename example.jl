# ===============================================================================
# Step 1: Load the tool =========================================================
# ===============================================================================

# Include all pipes and network related PipingTooltions
include("src/PipingTool.jl")
import .PipingTool

# Data handling
using CSV, DataFrames, NonlinearSolve, PrettyTables, Printf, Statistics, Unitful, DataStructures, OrderedCollections, PlotlyJS, GraphPlot, Graphs, Compose, Cairo, Fontconfig

scenarioName = "example"   # Used as folder name in output directory.

# ===============================================================================
# Step 2: Load your data ========================================================
# ===============================================================================

data = CSV.read("files/example/data_example.csv", DataFrame, header=1, skipto=2)

# ===============================================================================
# Step 3: Define your topology ==================================================
# ===============================================================================

# Principal parameters --------------------------
EnergyHub = "All"
nb_cluster = 6
ListOfNodes = names(select(data, Not(:TIME)))

# Define Topology -------------------------------
Topology = PipingTool.TopologyStruct.System("TopologyDetailed",
                Vector{PipingTool.TopologyStruct.Node}(), 
                Vector{PipingTool.TopologyStruct.Segment}(),
                Vector{PipingTool.TopologyStruct.Segment}(),                   
                EnergyHub)

# Define Nodes ----------------------------------
# Main loop nodes
PipingTool.TopologyStruct.add_new_node(Topology,EnergyHub,[], data)
PipingTool.TopologyStruct.add_new_node(Topology,"1", [], data)
PipingTool.TopologyStruct.add_new_node(Topology,"2", [], data)
PipingTool.TopologyStruct.add_new_node(Topology,"3", [], data)
PipingTool.TopologyStruct.add_new_node(Topology,"4", [], data)
PipingTool.TopologyStruct.add_new_node(Topology,"5", [], data)
PipingTool.TopologyStruct.add_new_node(Topology,"6", [], data)
# Building nodes
for i in 1:length(ListOfNodes)
    PipingTool.TopologyStruct.add_new_node(Topology, ListOfNodes[i], [ListOfNodes[i]], data)
end


# Define Segment --------------------------------
# Main supply
PipingTool.TopologyStruct.add_new_segment(Topology,EnergyHub, "1", 1)
PipingTool.TopologyStruct.add_new_segment(Topology,"1", "2", 425)
PipingTool.TopologyStruct.add_new_segment(Topology,"2", "3", 350)
PipingTool.TopologyStruct.add_new_segment(Topology,"3", "4", 200)
PipingTool.TopologyStruct.add_new_segment(Topology,"4", "5", 230)
PipingTool.TopologyStruct.add_new_segment(Topology,"5", "6", 375)

PipingTool.TopologyStruct.add_new_segment(Topology,"6", "9A", 70)
PipingTool.TopologyStruct.add_new_segment(Topology,"6", "10A", 60)
PipingTool.TopologyStruct.add_new_segment(Topology,"10A", "10B", 60)
PipingTool.TopologyStruct.add_new_segment(Topology,"10B", "10C", 60)

PipingTool.TopologyStruct.add_new_segment(Topology,"5", "1Aa", 100)
PipingTool.TopologyStruct.add_new_segment(Topology,"1Aa", "1Ab", 100)
PipingTool.TopologyStruct.add_new_segment(Topology,"5", "1Bb", 100)
PipingTool.TopologyStruct.add_new_segment(Topology,"1Bb", "1Ba", 100)

PipingTool.TopologyStruct.add_new_segment(Topology,"4", "2Ba", 30)
PipingTool.TopologyStruct.add_new_segment(Topology,"2Ba", "2Bb", 50)
PipingTool.TopologyStruct.add_new_segment(Topology,"4", "2Ca", 130)
PipingTool.TopologyStruct.add_new_segment(Topology,"2Ca", "2Cb", 40)
PipingTool.TopologyStruct.add_new_segment(Topology,"4", "2Ab", 60)
PipingTool.TopologyStruct.add_new_segment(Topology,"2Ab", "2Aa", 40)

PipingTool.TopologyStruct.add_new_segment(Topology,"3", "3Bc", 100)
PipingTool.TopologyStruct.add_new_segment(Topology,"3Bc", "11A", 50)
PipingTool.TopologyStruct.add_new_segment(Topology,"3", "3Aa", 100)
PipingTool.TopologyStruct.add_new_segment(Topology,"3Aa", "3Ab", 50)
PipingTool.TopologyStruct.add_new_segment(Topology,"3Aa", "3Ba", 50)
PipingTool.TopologyStruct.add_new_segment(Topology,"3Ba", "3Bb", 50)

PipingTool.TopologyStruct.add_new_segment(Topology,"2", "4B", 100)
PipingTool.TopologyStruct.add_new_segment(Topology,"4B", "4A", 50)
PipingTool.TopologyStruct.add_new_segment(Topology,"2", "5A", 120)
PipingTool.TopologyStruct.add_new_segment(Topology,"5A", "5B", 90)

PipingTool.TopologyStruct.add_new_segment(Topology,"1", "6A", 150)
PipingTool.TopologyStruct.add_new_segment(Topology,"1", "7A", 1)
PipingTool.TopologyStruct.add_new_segment(Topology,"1", "7B", 50)
PipingTool.TopologyStruct.add_new_segment(Topology,"7B", "7C", 120)
PipingTool.TopologyStruct.add_new_segment(Topology,"7C", "8A", 60)

# Define Cluster --------------------------------
PipingTool.TopologyStruct.add_new_cluster(Topology,"1")
PipingTool.TopologyStruct.add_new_cluster(Topology,"2")
PipingTool.TopologyStruct.add_new_cluster(Topology,"3")
PipingTool.TopologyStruct.add_new_cluster(Topology,"4")
PipingTool.TopologyStruct.add_new_cluster(Topology,"5")
PipingTool.TopologyStruct.add_new_cluster(Topology,"6")

# Distribute loads to Segments --------------------------------
PipingTool.TopologyStruct.get_SegmentLoads(Topology, EnergyHub)

PipingTool.TopologyStruct.see_graph(Topology, scenarioName)

# ===============================================================================
# Step 4: Define network operation parameters ===================================
# ===============================================================================

# Maximum pressure drop
Δp′_max = 220u"Pa/m"

# Temperature of supply and return loop
Ts = 75u"°C"
Tr = 45u"°C"
ΔT = Ts - Tr
T = Ts - ΔT/2

# Few other variables
prefix = "H-"           # Used as a prefix before each segment names in the pipe characteristics CSV file.
colName = "QHEATTOT"    # Used as the column name of each clusters loads file.
append = false          # Used to indicate if we append or overwrite the pipe characterisation file.

# ===============================================================================
# Step 5: Calling sizing PipingTooltion and agregation algorithm ======================
# ===============================================================================

# Sizing PipingTooltion ----------------------------------------
PipingTool.select_pipes(Topology, Ts, Tr, data, Δp′_max)
PipingTool.TopologyStruct.exportTopologySegment_ToCSV(Topology, scenarioName, prefix, append, colName)

# Simplified network algorithm ---------------------------
TopologySimplified = deepcopy(Topology)
TopologySimplified.Name = "TopologySimplified"

# Simpification algorithm
TopologySimplified = PipingTool.SimplifyingClusterAlgorithm(TopologySimplified)

# Save to CSV
PipingTool.TopologyStruct.see_graph(TopologySimplified, scenarioName)
PipingTool.TopologyStruct.exportTopologySegment_ToCSV(TopologySimplified, scenarioName, prefix, append, colName)

TopologyReduced = deepcopy(Topology)
TopologyReduced.Name = "TopologyReduced"

# Reduced network algorithm ------------------------------
# Collapsing algorithm
TopologyReduced = PipingTool.CollapsingClusterAlgorithm(TopologyReduced, T)

# Reducing algorithm
TopologyReduced = PipingTool.ReductingClusterAlgorithm(TopologyReduced, T, ΔT)

# Save to CSV
PipingTool.TopologyStruct.see_graph(TopologyReduced, scenarioName)
PipingTool.TopologyStruct.exportTopologySegment_ToCSV(TopologyReduced, scenarioName, prefix, append, colName)

# ===============================================================================
# End of example ================================================================
# ===============================================================================
