module TopologyStruct

export Node, Segment, Cluster, System, exportTopologySegment_ToCSV, see_graph, get_Node_ChildSegmentsAndNodes, get_SegmentLoads, add_new_cluster, add_new_node, add_new_segment

# Data handling
using CSV
using DataFrames
using NonlinearSolve
using PrettyTables
using Printf
using Statistics
using Unitful
using DataStructures
using OrderedCollections
# Graphics and Plotting
using PlotlyJS
using GraphPlot, Graphs, Compose, Cairo, Fontconfig


"""
    Node

Structure of node element for network graph. Attributes are:

- `id`: (*Int8*) Node unique id.
- `Name`: (*String*) Node unique name.
- `LoadsName`: (*Vector{String}*) Name of the loads column in loads dataframe, loads must be in kj/hr.
- `Q̇t`: (*Vector{Float64}*) Loads input for Node in kJ/hr.
"""
mutable struct Node
    id::Int8                   # Node  unique id [Int8]
    name::String               # Node  unique name [String]
    LoadsName::Vector{String}  # Name of the loads dataframe in kj/hr [String]
    Q̇t::Vector{Float64}        # Loads input for Node       [kJ/hr]
end

"""
    Segment

Structure for segment element of network graph. Attributes are:

- `id`: (*Int8*) Segment unique id.
- `name`: (*String*) Segment unique name.
- `FromTo`: (*Tuple{String, String}*) Couple of (Supply node ID, return node ID)
- `LoadsName`: (*Vector{String}*) Name of the loads column in loads dataframe, loads must be in kj/hr 
- `ṁ`: (*Float64*) [kg/s] Nominal flowrate in segment
- `Di`: (*Float64*) [m] Segment inner diameter
- `Do`: (*Float64*) [m] Segment outer diameter (before insulation)
- `L`: (*Float64*) [m] Segment length
- `A`: (*Float64*) [m²] Segment fluid area
- `e`: (*Float64*) [m] Insulation thickness
- `V`: (*Float64*) [m3] Volume of segment
- `Q̇`: (*Float64*) [kJ/hr] Nominal load in segment  
- `H`: (*Float64*) [W/(m.K)] heat conductivity of segment
"""
mutable struct Segment
    id::Int8                        # Segment unique id [Int8]
    name::String                    # Segment unique name [String]
    FromTo::Tuple{String, String}   # (Supply node ID, return node ID) [(String, String)]
    LoadsName::Vector{String}       # Name of the loads dataframe in kj/hr [String] >>>> CONVERT TO mdOT
    ṁ::Float64    # [kg/s]
    Di::Float64   # [m]
    Do::Float64   # [m]
    L::Float64    # [m]
    A::Float64    # [m²]
    e::Float64    # [m] Epaisseur d'isolant
    V::Float64    # [m3] Volume
    Q̇::Float64    # [kJ/hr] Maximum load in pipe  
    H::Float64    # [W/(m.K)] heat conductivity of pipe
end

"""
    Cluster

Structure for cluster element of network graph. A cluster element is defined at a node level (using the `node_name` attribute).
From this, assuming a tree-like structure (no loops), the child segments and nodes will be identified. Attributes are:

- `id`: (*Int8*) Cluster ID.
- `node_name`: (*String*) Cluster origin node name. Must be one of *Node* names.
- `node_id`: (*Int8*) Cluster origin node ID. Must be one of *Node* ID.
- `Segments_in_cluster`: (*Vector{String}*) List of all segments in cluster.
- `Loads_in_cluster`: (*Vector{String}*) List of all loads in cluster.
"""
mutable struct Cluster
    id::Int8
    node_name::String
    node_id::Int8
    Segments_in_cluster::Vector{String}
    Loads_in_cluster::Vector{String}
end

"""
    System

Structure for defining a complete network. Attributes are:

- `Name`: (*String*) Name of the network/topology
- `Nodes`: (*Vector{Node}*) contains all the network nodes.
- `Segments`: (*Vector{Segment}*) contains all the network segments.
- `Cluster`: (*Vector{Cluster}*) contains all the network clusters.
- `EnergyHub`: (*String*) Is the name of the node to use as a main station for equilibrating loads.
"""
mutable struct System
    Name::String
    Nodes::Vector{Node}
    Segments::Vector{Segment}
    Cluster::Vector{Cluster}
    EnergyHub::String
end


"""
    add_new_segment(Topology, From, To, Length)

Function to add a new segment to existing Topology (automatically handling segment id).

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `From`: (*String*) Name of a node. Origin of segment. 
- `To`: (*String*) Name of a node. Destination of segment.
- `Length`: (*Float64*) Length of segment.
"""
function add_new_segment(Topology, From, To, Length)
    id = length(Topology.Segments)+1
    push!(Topology.Segments, Segment(id, From*"_"*To, (From,To), [], 0.0, 0.0, 0.0, Length, 0.0, 0.0, 0.0, 0.0, 0.0))
end

"""
    add_new_node(Topology, name, LoadNames, QDataframe)
    
Function to add a new node to existing Topology (automatically handling node id).

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `name`: (*String*) Name of the node.
- `LoadNames`: (*Vector{String}*) List of loads columns that are to be associated to this node.
- `QDataframe`: (*DataFrame*) Dataframe where LoadsNames are to be found.
"""
function add_new_node(Topology, name, LoadNames, QDataframe)
    #N = Node(id, LoadNames, 0.0, 0.0, Vector{Float64}(undef, 8760), Vector{Float64}(undef, 8760))
    id = length(Topology.Nodes)+1
    Q̇t = QDataframe[!, names(QDataframe)[2]] .* 0.0
    if length(LoadNames)>0
        for el in LoadNames
            if el ∉ names(QDataframe)
                println(el*" not found in QDataframe columns")
            end
            Q̇t = Q̇t .+ QDataframe[!, el]
        end
    end

    push!(Topology.Nodes, Node(id, name, LoadNames, Q̇t))
end

"""
    add_new_cluster(Topology, name)
    
Function to add a new cluster to existing Topology (automatically handling cluster id).

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `name`: (*String*) Name of the node to take as cluster origin.
"""
function add_new_cluster(Topology, name)
    id = length(Topology.Cluster)+1
    node_id = 0
    for N in Topology.Nodes
        if N.name == name
            node_id = N.id
        end
    end
    if node_id == 0
        println("Wrong cluster name for "*name)
    end
    push!(Topology.Cluster, Cluster(id, name, node_id ,[], []))
end

"""
    get_SegmentLoads(Topology, EnergyHub)
    
Function to distribute all of nodes loads to segments of the topology. A loads flows from its origin node to the energy hub (defined as *EnergyHub*), loads is distributed to all segments it encounter in its path.

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `EnergyHub`: (*String*) Name of the node to take as the topology EnergyHub, where main station is located and where all loads flows to.
"""
function get_SegmentLoads(Topology, EnergyHub)

    # Distribute LoadNames to Segments ---------------------
    for node in Topology.Nodes
        # Initialize
        found = 0
        current_looking_node = node.name
        # Loop while not at the EnergyHub
        while current_looking_node != EnergyHub
            
            # Finding the next segment of the path
            for pipe in Topology.Segments
                if pipe.FromTo[2] == current_looking_node
                    for loads_item in node.LoadsName
                        push!(pipe.LoadsName, loads_item)
                    end
                    current_looking_node = pipe.FromTo[1]
                    found = 1
                end
            end
            
            # Checking that a segment is indeed found
            if found == 0
                println("Failing...")
            end
        end
    end
end

"""
    get_Node_ChildSegmentsAndNodes(Topology, N)

Function that return all child nodes and segments of a cluster origin node. Assuming tree-like topology without loop (single path from every node to cluster origin node).

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `N`: (*String*) Name of the node where cluster origin is located.
# Outputs
- `ChildList`: (*Vector{String}*) List of child nodes.
- `SegmentList`: (*Vector{String}*) List of child segments.
"""
function get_Node_ChildSegmentsAndNodes(Topology, N)
    # Get list of cluster's node id
    List_cluster_id = []
    for cluster in Topology.Cluster
        push!(List_cluster_id, cluster.node_name)
    end
    
    ChildList = []
    SegmentList = []
    # Get each cluster node childs and branch childs
    for node in Topology.Nodes

        # Initialize
        current_looking_node = node.name
        child_nodes = []
        child_branches = []

        # Get child branches to cluster node
        node_checked = 0
        N_found = false
        while (current_looking_node ∉ List_cluster_id && node_checked < length(Topology.Nodes))
            # Finding the next segment of the path
            for pipe in Topology.Segments
                if pipe.FromTo[2] == current_looking_node
                    push!(child_nodes, pipe.FromTo[2])
                    push!(child_branches, pipe.name)
                    current_looking_node = pipe.FromTo[1]
                end
            end
            node_checked += 1
        end
        
        # Check reason of output
        if current_looking_node == N
            for child_node in child_nodes
                for n in Topology.Nodes
                    if (n ∉ ChildList) && (n.name == child_node)
                        push!(ChildList, n)
                    end
                end
            end
            for child_branch in child_branches
                for seg in Topology.Segments
                    if (seg ∉ SegmentList) && (seg.name == child_branch)
                        push!(SegmentList, seg)
                    end
                end
            end
        end
    end
    return ChildList, SegmentList
end

"""
    see_graph(Topology)

Function that use SimpleGraph representation to display node topology as a beautiful figure.

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `scenarioName`: (*String*) Name of folder of scenario for output png.

"""
function see_graph(Topology, scenarioName)

    g = SimpleGraph(length(Topology.Nodes))
    nodelabell = []
    for n in 1:length(Topology.Nodes)
        push!(nodelabell, Topology.Nodes[n].name) 
    end
    for s in Topology.Segments
        sFrom = s.FromTo[1]
        sTo = s.FromTo[2]
        n_sFrom, n_sTo = 0,0
        for n in 1:length(Topology.Nodes)
            nodelabell[n] = Topology.Nodes[n].name

            if Topology.Nodes[n].name == sFrom
                n_sFrom = n
            end
            if Topology.Nodes[n].name == sTo
            n_sTo = n
            end
        end
        add_edge!(g,n_sFrom,n_sTo)
    end


    display((gplot(g, nodelabel=nodelabell)))
    mkpath("output/")
    mkpath("output/"*scenarioName*"/")
    draw(PNG("output/"*scenarioName*"/"*Topology.Name*".png", 16cm, 16cm), gplot(g, nodelabel=nodelabell))
end

"""
    exportTopologySegment_ToCSV(Topology, scenarioName, prefix, append, colName)

Function that export the network topology as different CSV files. Generate one CSV for pipes parameters and one CSV file for each clusters for their loads.

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `scenarioName`: (*String*) Folder of the scenario where to generate the CSV of topology.
- `prefix`: (*String*) Prefix to use before each segment name.
- `append`: (*Boolean*) True or False for appending an existing CSV file. 
- `colName`: (*String*) Name of the column for cluster loads files.
"""
function exportTopologySegment_ToCSV(Topology, scenarioName, prefix, append, colName)

    # ----------------------------------
    # Save pipe characteristics --------
    # ----------------------------------

    # Update  Topology
    get_SegmentLoads(Topology, "All")

    # Save each segment as a file
    name, L ,Q̇, Di, Do, e, H, ṁ = ["-"],["[m]"],["[kJ/hr]"],["[m]"],["[m]"],["[m]"],["[W/K]"], ["kg/hr"]
    for p in Topology.Segments
        push!(name, prefix*p.name)
        push!(L, string(p.L))
        push!(Di, string(p.Di))
        push!(Do, string(p.Do))
        push!(e, string(p.e))
        push!(Q̇, string(p.Q̇))      # kJ/hr
        push!(ṁ, string(p.ṁ*3600)) # kg/s > kg/hr
        push!(H, string(p.H))      # W/K >
    end
    # Build DF
    DF = DataFrame(name=name, L=L, Q=Q̇, Di=Di, Do=Do, e=e, H=H, mdot=ṁ)

    # ----------------------------------
    # Save load files ------------------
    # ----------------------------------
    mkpath("output/")
    mkpath("output/"*scenarioName*"/")
    mkpath("output/"*scenarioName*"/"*Topology.Name*"/")
    mkpath("output/"*scenarioName*"/"*Topology.Name*"/"*"input/")
    
    # Save table of reference data
    CSV.write("output/"*scenarioName*"/"*Topology.Name*"/pipe.csv", DF, append=append)
    TotNodes = DataFrame(TIME=1:8761)

    for node in Topology.Nodes
        if maximum(node.Q̇t) > 1
            t = 1:8761
            nodeDF = DataFrame(TIME=t)
            try
                nodeDF = CSV.read("output/"*scenarioName*"/"*Topology.Name*"/input/"*node.name*".csv", DataFrame, header=1, skipto=2)
            catch
                nodeDF = DataFrame(TIME=t)
            end
            nodeDF[!,colName] = node.Q̇t

            try
                TotNodes[!,colName] = TotNodes[!,colName] .+  node.Q̇t
            catch
                TotNodes[!,colName] = node.Q̇t
            end

            CSV.write("output/"*scenarioName*"/"*Topology.Name*"/input/"*node.name*".csv", nodeDF)
        end
    end
end

end   # module 