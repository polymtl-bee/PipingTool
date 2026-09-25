# ===============================================================================
# Step 1: Load the tool =========================================================
# ===============================================================================

# Include all pipes and network related functions
include("Lib/functions.jl")
import .func

# Data handling
using CSV, DataFrames, NonlinearSolve, PrettyTables, Printf, Statistics
using Unitful, DataStructures, OrderedCollections, PlotlyJS
using GraphPlot, Graphs, Compose, Cairo, Fontconfig

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
Topology = func.TopologyStruct.System("TopologyDetailed",
                Vector{func.TopologyStruct.Node}(), 
                Vector{func.TopologyStruct.Segment}(),
                Vector{func.TopologyStruct.Segment}(),                   
                EnergyHub)

# Define Nodes ----------------------------------
# Main loop nodes
func.TopologyStruct.add_new_node(Topology,EnergyHub,[], data)
func.TopologyStruct.add_new_node(Topology,"1", [], data)
func.TopologyStruct.add_new_node(Topology,"2", [], data)
func.TopologyStruct.add_new_node(Topology,"3", [], data)
func.TopologyStruct.add_new_node(Topology,"4", [], data)
func.TopologyStruct.add_new_node(Topology,"5", [], data)
func.TopologyStruct.add_new_node(Topology,"6", [], data)
# Building nodes
for i in 1:length(ListOfNodes)
    func.TopologyStruct.add_new_node(Topology, ListOfNodes[i], [ListOfNodes[i]], data)
end


# Define Segment --------------------------------
# Main supply
func.TopologyStruct.add_new_segment(Topology,EnergyHub, "1", 1)
func.TopologyStruct.add_new_segment(Topology,"1", "2", 425)
func.TopologyStruct.add_new_segment(Topology,"2", "3", 350)
func.TopologyStruct.add_new_segment(Topology,"3", "4", 200)
func.TopologyStruct.add_new_segment(Topology,"4", "5", 230)
func.TopologyStruct.add_new_segment(Topology,"5", "6", 375)

func.TopologyStruct.add_new_segment(Topology,"6", "9A", 70)
func.TopologyStruct.add_new_segment(Topology,"6", "10A", 60)
func.TopologyStruct.add_new_segment(Topology,"10A", "10B", 60)
func.TopologyStruct.add_new_segment(Topology,"10B", "10C", 60)

func.TopologyStruct.add_new_segment(Topology,"5", "1Aa", 100)
func.TopologyStruct.add_new_segment(Topology,"1Aa", "1Ab", 100)
func.TopologyStruct.add_new_segment(Topology,"5", "1Bb", 100)
func.TopologyStruct.add_new_segment(Topology,"1Bb", "1Ba", 100)

func.TopologyStruct.add_new_segment(Topology,"4", "2Ba", 30)
func.TopologyStruct.add_new_segment(Topology,"2Ba", "2Bb", 50)
func.TopologyStruct.add_new_segment(Topology,"4", "2Ca", 130)
func.TopologyStruct.add_new_segment(Topology,"2Ca", "2Cb", 40)
func.TopologyStruct.add_new_segment(Topology,"4", "2Ab", 60)
func.TopologyStruct.add_new_segment(Topology,"2Ab", "2Aa", 40)

func.TopologyStruct.add_new_segment(Topology,"3", "3Bc", 100)
func.TopologyStruct.add_new_segment(Topology,"3Bc", "11A", 50)
func.TopologyStruct.add_new_segment(Topology,"3", "3Aa", 100)
func.TopologyStruct.add_new_segment(Topology,"3Aa", "3Ab", 50)
func.TopologyStruct.add_new_segment(Topology,"3Aa", "3Ba", 50)
func.TopologyStruct.add_new_segment(Topology,"3Ba", "3Bb", 50)

func.TopologyStruct.add_new_segment(Topology,"2", "4B", 100)
func.TopologyStruct.add_new_segment(Topology,"4B", "4A", 50)
func.TopologyStruct.add_new_segment(Topology,"2", "5A", 120)
func.TopologyStruct.add_new_segment(Topology,"5A", "5B", 90)

func.TopologyStruct.add_new_segment(Topology,"1", "6A", 150)
func.TopologyStruct.add_new_segment(Topology,"1", "7A", 1)
func.TopologyStruct.add_new_segment(Topology,"1", "7B", 50)
func.TopologyStruct.add_new_segment(Topology,"7B", "7C", 120)
func.TopologyStruct.add_new_segment(Topology,"7C", "8A", 60)

# Define Cluster --------------------------------
func.TopologyStruct.add_new_cluster(Topology,"1")
func.TopologyStruct.add_new_cluster(Topology,"2")
func.TopologyStruct.add_new_cluster(Topology,"3")
func.TopologyStruct.add_new_cluster(Topology,"4")
func.TopologyStruct.add_new_cluster(Topology,"5")
func.TopologyStruct.add_new_cluster(Topology,"6")

# Distribute loads to Segments --------------------------------
func.TopologyStruct.get_SegmentLoads(Topology, EnergyHub)

func.TopologyStruct.see_graph(Topology, scenarioName)

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
# Step 5: Calling sizing function and agregation algorithm ======================
# ===============================================================================

# Sizing function ----------------------------------------
func.select_pipes(Topology, Ts, Tr, data, Δp′_max)
func.TopologyStruct.exportTopologySegment_ToCSV(Topology, scenarioName, prefix, append, colName)

# Simplified network algorithm ---------------------------
TopologySimplified = deepcopy(Topology)
TopologySimplified.Name = "TopologySimplified"

# Simpification algorithm
TopologySimplified = func.SimplifyingClusterAlgorithm(TopologySimplified)

# Save to CSV
func.TopologyStruct.see_graph(TopologySimplified, scenarioName)
func.TopologyStruct.exportTopologySegment_ToCSV(TopologySimplified, scenarioName, prefix, append, colName)

TopologyReduced = deepcopy(Topology)
TopologyReduced.Name = "TopologyReduced"

# Reduced network algorithm ------------------------------
# Collapsing algorithm
TopologyReduced = func.CollapsingClusterAlgorithm(TopologyReduced, T)

# Reducing algorithm
TopologyReduced = func.ReductingClusterAlgorithm(TopologyReduced, T, ΔT)

# Save to CSV
func.TopologyStruct.see_graph(TopologyReduced, scenarioName)
func.TopologyStruct.exportTopologySegment_ToCSV(TopologyReduced, scenarioName, prefix, append, colName)

# ===============================================================================
# End of example ================================================================
# ===============================================================================
