module PipingTool

export select_pipes, CollapsingClusterAlgorithm, ReductingClusterAlgorithm, SimplifyingClusterAlgorithm

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
# Thermal properties of water (warning: old implementation, not compatible with Unitful, check help for correct units)
include("WaterProperties.jl")
import .WaterProperties
include("TopologyStruct.jl")
import .TopologyStruct

# =========================================================================
# Pipe selection functions  ===============================================
# =========================================================================
 
"""
    select_pipes(Topology, Tsupply, Treturn, QDataframe, Δp′_max)

This function will calulate each segments properties following the steps described below:

1. Calculate design temperature conditions ('ΔT= Tsupply - Treturn' and 'T = Tsupply - ΔT/2') and water properties ('cₚ', 'rho' and 'mu').
2. Get nominal loads 'Q̇max' and nominal flowrate 'ṁ' for each pipe.
3. Load pipes reference data file.
4. Calculate pressure drop for each segment using Reynolds number and Darcy-Weisbach equations.
5. Choose appropriate reference pipe for each segment.
6. Save properties of each segments using their chosen reference pipe. 

# Arguments
- `Topology`: (*System*) A System struct object of a network topology.
- `Tsupply`: (*Float64*) [°C] Supply temperature of pipes in network. 
- `Treturn`: (*Float64*) [°C] Return temperature of pipes in network. 
- `QDataframe`: (*DataFrame*) Dataframe where loads are to be found (used for maximum loads and flowrate calculation).
- `Δp′_max`: (*Float64*) [Pa/m] Maximum authorized pressure drop in segments.
"""
function select_pipes(Topology, Tsupply, Treturn, QDataframe, Δp′_max)
    
    # ------------------------------------------------------------------------------------------------------------------------
    #region: Design and water properties -------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------------------------------
    
    # Design temperatures
    ΔT = ustrip(Tsupply - Treturn) * u"K"

    # Get water properties
    T = ustrip(Tsupply - ΔT/2 |> u"°C")
    cₚ = WaterProperties.specheat(T) * u"J/(kg*K)"
    rho = WaterProperties.density(T) * u"kg/m^3"
    mu = WaterProperties.dynviscosity(T) * u"kg/(m*s)"

    # ------------------------------------------------------------------------------------------------------------------------
    #region: Get Q̇max and ṁ for each pipe  -----------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------------------------------
    
    for pipe in Topology.Segments
        
        # Get 1st column to use for max
        Q_load = QDataframe[!, pipe.LoadsName[1]]  # [kJ/hr]
 
        # Get all other columns
        nb_loads = length(pipe.LoadsName)
        if nb_loads > 1
            for index in range(2, nb_loads)
                Q_load += QDataframe[!, pipe.LoadsName[index]]
            end
        end

        # Max & Save
        pipe.Q̇ = maximum(Q_load)    # kJ/hr 
        pipe.ṁ = (1000*pipe.Q̇) / (ustrip(cₚ) * ustrip(ΔT))/3600 # kg/hr ---- /1000/3600 # kg/s

    end

    # ------------------------------------------------------------------------------------------------------------------------
    #region: Load selected pipes reference data file -------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------------------------------

    fname = "src/Typical piping sizes and properties.csv"
    pipes_ref = CSV.read(fname, DataFrame, header=3, skipto=5)
    units = CSV.read(fname, DataFrame, header=3, skipto=4, stringtype=String, limit=1)
    for name in names(pipes_ref)
        if units[1, name] == "h"
            units[1, name] = "hr" # In Unitful, h is the Planck constant
        end
        pipes_ref[!, name] .= pipes_ref[!, name] * uparse(units[1, name])
    end

    # Get pipe volume
    pipes_ref.vol′ = π * pipes_ref.di.^2 / 4  

    # Thermal losses (do not depend on flow rate)
    k_ins = 0.027u"W/(m*K)"
    pipes_ref.e_c1 = (pipes_ref.do_ins_c1 .- pipes_ref.do_pipe) / 2   # [m]
    pipes_ref.e_c2 = (pipes_ref.do_ins_c2 .- pipes_ref.do_pipe) / 2   
    pipes_ref.e_c3 = (pipes_ref.do_ins_c3 .- pipes_ref.do_pipe) / 2
    pipes_ref.R′_c1 = log.(pipes_ref.do_ins_c1 ./ pipes_ref.do_pipe) ./ (2 * π * k_ins)   # sK.M/W
    pipes_ref.R′_c2 = log.(pipes_ref.do_ins_c2 ./ pipes_ref.do_pipe) ./ (2 * π * k_ins)
    pipes_ref.R′_c3 = log.(pipes_ref.do_ins_c3 ./ pipes_ref.do_pipe) ./ (2 * π * k_ins)
    pipes_ref.UA′_c1 = 1 ./ pipes_ref.R′_c1
    pipes_ref.UA′_c2 = 1 ./ pipes_ref.R′_c2
    pipes_ref.UA′_c3 = 1 ./ pipes_ref.R′_c3


    # ------------------------------------------------------------------------------------------------------------------------
    #region: Get pipe characteristics for each Segment -----------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------------------------------
    # Calculate pressure drop for each power value and print table with pipe size for each of them

    # Initialize dataframe of selected pipes with first pipe
    first_pipe = Topology.Segments[1]
    dummy, dummy2 = calcpressuredrop(pipes_ref, first_pipe.Q̇ *u"kJ/hr" , ΔT, cₚ, rho, mu)
    i1 = findfirst(dummy.Δp′ .<= Δp′_max)
    ref_pipe_for_segment = dummy[i1:i1, :]
    # Store pipe data to Segment
    first_pipe.Di   = ustrip(ref_pipe_for_segment.di[1])
    first_pipe.Do   = ustrip(ref_pipe_for_segment.do_pipe[1])
    first_pipe.V    = first_pipe.L * (first_pipe.Di * first_pipe.Di * 3.14)
    first_pipe.A    = 3.1416 * first_pipe.Di * first_pipe.Di
    first_pipe.H    = ustrip(ref_pipe_for_segment.UA′_c2[1]) * first_pipe.L
    first_pipe.e    = ustrip(ref_pipe_for_segment.e_c2[1])
       
    # Store ref pipe to ref pipe table
    selected_pipes = dummy[i1:i1, :]

    # Loop for all other pipes
    for pipe in Topology.Segments[2:end]
        
        # Get reference pipe
        dummy, dummy2 = calcpressuredrop(pipes_ref, pipe.Q̇ *u"kJ/hr", ΔT, cₚ, rho, mu)
        i1 = findfirst(dummy.Δp′ .<= Δp′_max)
        ref_pipe_for_segment = dummy[i1:i1, :]
        
        # Store pipe data to Segment
        pipe.Di   = ustrip(ref_pipe_for_segment.di[1])
        pipe.Do   = ustrip(ref_pipe_for_segment.do_pipe[1])
        pipe.A    = 3.1416/4 * pipe.Di * pipe.Di
        pipe.V    = pipe.L * pipe.A
        pipe.H    = ustrip(ref_pipe_for_segment.UA′_c2[1]) * pipe.L
        pipe.e    = ustrip(ref_pipe_for_segment.e_c2[1])
        
        # Store ref pipe to ref pipe table
        selected_pipes = vcat(selected_pipes, dummy[i1:i1, :])    # [i1,:] returns a DataFrameRow, not a DataFrame, and then concatenation does not work
    end


    # ------------------------------------------------------------------------------------------------------------------------
    #region: Build table of reference pipe  ----------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------------------------------
    
    # Get new columns data
    allL, allQ̇, allN= [], [], []
    for pipe in Topology.Segments
        push!(allQ̇, pipe.Q̇*u"kW")
        push!(allN, pipe.name)
        push!(allL, pipe.L)
    end

    # Add new columns
    selected_pipes_totable = ustrip.(selected_pipes)
    insertcols!(selected_pipes_totable, 1, :Q̇ => allQ̇)
    insertcols!(selected_pipes_totable, 1, :Q̇bldg => allQ̇)
    insertcols!(selected_pipes_totable, 1, :length => allL)
    insertcols!(selected_pipes_totable, 1, :Name => allN)

    #println()
    #println("Pipe selection ($Tsupply / $Treturn), Tavg = $T, ΔT = $ΔT")
    pretty_table(selected_pipes, show_first_column_label_only=true, fit_table_in_display_horizontally = false)
    
    # ------------------------------------------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------------------------------
end


# Calculate velocity and pressure drop for different pipe sizes

function calcpressuredrop(pipes, Q̇, ΔT, cₚ, rho, mu)

    ΔT = ustrip(u"K", ΔT)
    cₚ = ustrip(u"J/(kg*K)", cₚ) 
    rho = ustrip(u"kg/m^3", rho)
    mu = ustrip(u"kg/(m*s)", mu)
    Q̇  = ustrip(u"W", Q̇)

    # Mass flow rate [J/s /J*kg*K /K] = [kg/s]
    ṁ = Q̇ / (cₚ * ΔT)

    # Volumetric flow rate [kg/s / kg*m3] = [m3/s]
    V̇ = ṁ / rho

    pipes.V̇ .= V̇ * 1000 * u"L/s"

    # @printf("Q̇ = %g MW (%g kW)\n", Q̇ / 1e6, Q̇ / 1000)
    # @printf("ṁ = %g kg/s (%g kg/h)\n", ṁ, ṁ * 3600)
    # @printf("V̇ = %g m³/s (%g m³/h)\n", V̇, V̇ * 3600)

    # Velocity [m/s]
    pipes.u = V̇ ./ (π * ustrip.(u"m", pipes.di) .^ 2 / 4)
    # Reynolds number [kg/m3 * m /s * m / kg * m * s] = [-]
    pipes.Re = rho .* pipes.u .* ustrip.(u"m", pipes.di) ./ mu


    pipes.f = missings(Float64, nrow(pipes))
    pipes.fok = missings(Bool, nrow(pipes))
    pipes.Δp′ = missings(Float64, nrow(pipes))

    for i = 1:nrow(pipes)
        Re = ustrip(upreferred(pipes.Re[i]))
        dₕ = ustrip(u"m", pipes.di[i])
        ε = 0.01 / 1000    # Absolute roughness: 0.01 mm
        sol = solve(IntervalNonlinearProblem(fun, (0.0, 1.0), [ε, dₕ, Re]), abstol=1e-9, reltol=1e-9)
        # println("Algorithm: $(solution.alg)")
        # println("Solution: $(solution.u)")
        # println("Residual: $(solution.resid)")
        # println("Return code: $(solution.retcode)")
        # println("Return code successful (SciMLBase.successful_retcode(solution)) $(SciMLBase.successful_retcode(solution))")
        f = sol.u
        pipes.f[i] = f
        pipes.fok[i] = abs(sol.resid) < 1e-6
        if (!pipes.fok[i])
            @warn "Residual in solving for f is too large ($(sol.resid)). Convergence was probably not attained."
        end
        # Darcy-Weisbach equation [? * kg/m3 * m²/s² /m]
        Δp′ = f * rho * pipes.u[i]^2 / (2 * dₕ)
        pipes.Δp′[i] = Δp′
    end
    pipes = dropmissing(pipes) # Just to remove the question marks from column types
    allpipes = copy(pipes)

    # find dp1 (pressure drop in Pa per meter) within 150 and 300, and keep one diameter before and after 
    # (minimum 3 rows will be kept, except if 2 successive pipe sizes result in dp1 > 300 and dp1 < 150)

    i1 = findfirst(pipes.Δp′ .< 300)
    if isnothing(i1)
        i1 = 1
    end
    i1 = max(i1 - 1, 1)
    i2 = findlast(pipes.Δp′ .> 150)
    if isnothing(i2)
        i2 = size(pipes, 1)
    end
    i2 = min(i2 + 1, size(pipes, 1))
    pipes[i1:i2, :]

    # Put back units
    allpipes.u = allpipes.u .* u"m/s"
    allpipes.Δp′ = allpipes.Δp′ .* u"Pa/m"
    pipes.u = pipes.u .* u"m/s"
    pipes.Δp′ = pipes.Δp′ .* u"Pa/m"

    # return pipes[i1:i2, [:DN, :di, :do_pipe, :vol′, :u, :Re, :Δp′, :e_c1, :UA′_c1, :e_c2, :UA′_c2, :e_c3, :UA′_c3]]
    return pipes[i1:i2, [:V̇, :DN, :di, :do_pipe, :Δp′, :e_c2, :UA′_c2, :vol′, :u, :Re]], allpipes[:, [:DN, :di, :do_pipe, :Δp′, :e_c2, :UA′_c2, :vol′, :u, :Re]]

end

# Friction coefficient: Colebrook-White equation formulated as fun(f)=0
function fun(f, p)
    ε, dₕ, Re = p
    fun = 1 / sqrt(f) + 2 * log10(ε / (3.71 * dₕ) + 2.51 / (Re * sqrt(f)))
end

# =========================================================================
# Utility functions =======================================================
# =========================================================================

# Collapsing full network cluster
"""
    CollapsingClusterAlgorithm(Topology, T)

Full algorithm for collapsing branches of every cluster of a network. Will use successively the *CollapsingParallel* function in each cluster until all branches are collapsed and cluster is a line of segments.

# Arguments
- `Topology`: (*System*) A System struct object of the reference network topology.
- `T`: (*Float64*) [°C]  Mean temperature of pipes in network. 
# Outputs
- `Topology`: (*System*) A System struct object of the collapsed network topology, .
"""
function CollapsingClusterAlgorithm(Topology, T)
    for cluster in Topology.Cluster
        
        # 0/ Initialize cluster collapsing -----------------------------
        cluster_node = Topology.Nodes[cluster.node_id]
        pipe1 = TopologyStruct.Segment(1, "_", ("From","To"), [], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        pipe2 = TopologyStruct.Segment(1, "_", ("From","To"), [], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        do_collapse = true

        # 2/ 
        while do_collapse == true
            
            # 0/ Initialize -------------------------------------------------
            do_collapse = false

            # 1/ Get subgroup of branches to Collapse -----------------------
            # Get childs
            subgroup_nodes, subgroup_segments =  TopologyStruct.get_Node_ChildSegmentsAndNodes(Topology, cluster.node_name)
            # Add cluster node
            push!(subgroup_nodes, cluster_node)

            # 2/ Collapsing algorithm fur subgroup of segments --------------
            # Check for branch intersection in subtree
            for node in subgroup_nodes
                for seg1 in subgroup_segments
                    for seg2 in subgroup_segments
                        # Branch intersection if two distinct segments have same origin
                        if (seg1.FromTo[1] == node.name) && (seg2.name != seg1.name) && (seg2.FromTo[1] == node.name) 
                            do_collapse = true
                            pipe1 = seg1
                            pipe2 = seg2
                        end
                    end
                end
            end

            # 3/ Collapse ---------------------------------------------------
            if do_collapse == true
                Topology = CollapsingParallel(Topology, pipe1, pipe2, T)
                println("Collapsing - "*pipe1.name*" / "*pipe2.name)
            end
        end
    end
    return Topology
end

"""
    ReductingClusterAlgorithm(Topology, T, ΔT)

Full algorithm for reducing branches of every cluster of a network. Will use successively the *ReducingSerialDanish* function in each cluster until cluster is reduced to a 3 nodes line.

![Example of network simplified](img/ReducedTopology.png)

# Arguments
- `Topology`: (*System*) A System struct object of the reference network topology.
- `T`: (*Float64*) [°C]  Mean temperature of pipes in network. 
- `ΔT`: (*Float64*) [°C]  Difference of temperature between supply and return pipes in the network. 
# Outputs
- `Topology`: (*System*) A System struct object of the reduced network topology, .
"""
function ReductingClusterAlgorithm(Topology, T, ΔT)

    for cluster in Topology.Cluster
        
        # Initialize cluster reducing:
        cluster_node = Topology.Nodes[cluster.node_id]
        R1 = TopologyStruct.Segment(1, "_", ("From","To"), [], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        R2 = TopologyStruct.Segment(1, "_", ("From","To"), [], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        R3 = TopologyStruct.Segment(1, "_", ("From","To"), [], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        do_reduce = true

        # Reducing algorithm fur subgroup of segments:
        while do_reduce == true
            
            # 0/ Initialize -------------------------------------------------
            do_reduce = false

            # 1/ Get subgroup of branches to reduce -----------------------
            # Get childs
            subgroup_nodes, subgroup_segments =  TopologyStruct.get_Node_ChildSegmentsAndNodes(Topology, cluster.node_name)
            # Add cluster node

            # 2/ Check for danish method's scheme in subtree
            for node in subgroup_nodes
                for seg1 in subgroup_segments
                    for seg2 in subgroup_segments
                        for seg3 in subgroup_segments

                            # Branch intersection if two distinct segments have same origin
                            if (node.name == seg1.FromTo[1]) && (seg1.FromTo[2] == seg2.FromTo[1]) && (seg2.FromTo[2] == seg3.FromTo[1]) 
                                do_reduce = true
                                R1 = seg1
                                R2 = seg2                               
                                R3 = seg3
                            end
                        end
                    end
                end
            end

            # 3/ Collapse ---------------------------------------------------
            if do_reduce == true
                Topology = ReducingSerialDanish(Topology, R1, R2, R3, T)
                println("Reducing - "*R1.name*" / "*R2.name*" / "*R3.name)
            end
        end

        # Rename nodes & segments
        subgroup_nodes, subgroup_segments =  TopologyStruct.get_Node_ChildSegmentsAndNodes(Topology, cluster.node_name)
        for seg1 in subgroup_segments
            for seg2 in subgroup_segments
                for seg3 in subgroup_segments
                    if (cluster_node.name == seg1.FromTo[1]) && (seg1.FromTo[2] == seg2.FromTo[1]) && (seg2.FromTo[2] == seg3.FromTo[1])
                        oldn1name = seg1.FromTo[2]
                        oldn2name = seg2.FromTo[2]
                        oldn3name = seg3.FromTo[2]
                        for n in subgroup_nodes
                            if n.name == oldn1name
                                n.name = cluster_node.name*"close"
                            end
                            if n.name == oldn2name
                                n.name = cluster_node.name*"middle"
                            end
                            if n.name == oldn3name
                                n.name = cluster_node.name*"far"
                            end
                        end
                        seg1.FromTo = (cluster_node.name, cluster_node.name*"close")
                        seg2.FromTo = (cluster_node.name*"close", cluster_node.name*"middle")
                        seg3.FromTo = (cluster_node.name*"middle", cluster_node.name*"far")
                   
                        seg1.name = seg1.FromTo[1]*"_"*seg1.FromTo[2]
                        seg2.name = seg2.FromTo[1]*"_"*seg2.FromTo[2]
                        seg3.name = seg3.FromTo[1]*"_"*seg3.FromTo[2]

                    end
                end
            end
        end
        for n in subgroup_nodes
       
        end
        """
        subgroup_nodes, subgroup_segments =  TopologyStruct.get_Node_ChildSegmentsAndNodes(Topology, cluster.node_name)

        for seg1 in subgroup_segments
            for seg2 in subgroup_segments
                if (cluster_node.name == seg1.FromTo[1]) && (seg1.FromTo[2] == seg2.FromTo[1])                                 
                    Rlast1 = seg1
                    Rlast2 = seg2     
                    Topology = ReducingSerialDanishR3null(Topology, Rlast1, Rlast2, T)
                end
            end
        end
        """
    end
    return Topology
end

"""
    SimplifyingClusterAlgorithm(Topology)

Full algorithm for simplifying branches of every cluster of a network. 
Will calculate an equivalent node and an equivalent segment for every cluster; representing clusters as one equivalent node and segment.
This method preserve pipes insulation factor k_ins [W/m*K], total volume of fluid [m3] and total heat losses [W/K].

![Example of network simplified](img/RealTopology.png)

# Arguments
- `Topology`: (*System*) A System struct object of the reference network topology.
# Outputs
- `Topology`: (*System*) A System struct object of the simplified network topology, .
"""
function SimplifyingClusterAlgorithm(Topology)

    for cluster in Topology.Cluster
        
        # Initialize cluster reducing:
        cluster_node = Topology.Nodes[cluster.node_id]
        subgroup_nodes, subgroup_segments =  TopologyStruct.get_Node_ChildSegmentsAndNodes(Topology, cluster.node_name)
        # Select base pipe as the  one with the largest diameter
        dmax = 0
        pipe_eq = subgroup_segments[1]
        for pipe in subgroup_segments
            if pipe.Di > dmax
                dmax = pipe.Di
                pipe_eq = pipe
            end
        end
        
        # -----------------------------------------------------------
        # Preserved variables
        # -----------------------------------------------------------

        k_ins = 0.027* u"W/(m*K)"

        # Constants variables to keep in equivalent pipe
        Heq, Veq  = 0.0*u"W/K", 0.0*u"m*m*m"
        for pipe in subgroup_segments
            Heq  += pipe.H * u"W/K" 
            Veq += pipe.V *u"m*m*m"
        end

        # -----------------------------------------------------------
        # Equivalent length of largest pipe for total volume
        # -----------------------------------------------------------

        L_eq = Veq / (pipe_eq.A *u"m*m")
        UA′_eq = Heq / L_eq
        R′_eq = 1 / UA′_eq
        Eeq = ((exp(2*π*k_ins*R′_eq) * pipe_eq.Do) - pipe_eq.Do)/2
        
        pipe_eq.name = string(cluster_node.name)*"_N"*string(cluster_node.name)
        pipe_eq.L = ustrip(L_eq)
        pipe_eq.H = ustrip(Heq)
        pipe_eq.e = ustrip(Eeq) 
        
        # -----------------------------------------------------------
        # Build equivalent Node
        # -----------------------------------------------------------
        Q̇tot = subgroup_nodes[1].Q̇t .* 0.0
        for n in subgroup_nodes
            Q̇tot = Q̇tot .+ n.Q̇t
        end
        for n in subgroup_nodes
            if n.name == pipe_eq.FromTo[2]
                n.Q̇t = Q̇tot
                n.name = "N"*string(cluster_node.name)
                pipe_eq.FromTo = (cluster_node.name, n.name)
            end
        end
        pipe_eq.Q̇ = maximum(Q̇tot)

        # -----------------------------------------------------------
        # Remove all other cluster's node & segment
        # -----------------------------------------------------------
        for s in subgroup_segments
            if s.name != pipe_eq.name
                deleteat!(Topology.Segments, s.id) 
                for i in 1:length(Topology.Segments)
                    Topology.Segments[i].id = i
                end
            end
        end
        for n in subgroup_nodes
            if (n.name != pipe_eq.FromTo[2]) 
                deleteat!(Topology.Nodes, n.id) 
                for i in 1:length(Topology.Nodes)
                    Topology.Nodes[i].id = i
                end
            end
        end
        # -----------------------------------------------------------

    end
    return Topology
end

# Methods used for collapsing/Reducing network

"""
    CollapsingParallel(Topology, pipe1, pipe2, T)

Function for Collapsing branch *pipe1* on branch *pipe2*. Will result in two equivalent branches as shown on figure.
Using Larsen et al. (2002) method for collapsing branches described in [this paper](https://www.sciencedirect.com/science/article/pii/S0196890401000930?via%3Dihub).
This method preserve pipes insulation factor k_ins [W/m*K], total volume of fluid [m3] and total heat losses [W/K], and loads delay.

![Danish method schema](img/CollapsingBranches.png)

# Arguments
- `Topology`: (*System*) A System struct object of the reference network topology.
- `pipe1`: (*Segment*) A Segment struct object where *pipe2* will be collapsed.
- `pipe2`: (*Segment*) The Segment struct object that will be collapsed on *pipe1*. Origin of segment must be the same as *pipe1*.
- `T`: (*Float64*) [°C]  Mean temperature of pipes in network. 
# Outputs
- `Topology`: (*System*) A System struct object of network topology after the collapsing algorithm.
"""
function CollapsingParallel(Topology, pipe1, pipe2, T)

    # From:
    # (K0v) ----- R2 ----- (K2v)
    #   |  \                 |
    # <VB0> \              <VB2>
    #   |    R1              |
    # (K0v) --\-- R2 ----- <K2r>
    #     \    \
    #      \  (K1v)
    #      R1   |
    #        \<VB1>
    #         \ |
    #         (K1r)

    # To:
    # (K0v) ---RA--- (KAv) ---RB--- (KBv)  
    #   |              |              |
    # <VB0>          <VBA>          <VBB>
    #   |              |              |
    # (K0r) ---RA--- (KAv) ---RB--- (KBv) 

    # Variables ------------------------------------------
    # Pipe variables

    # Di   [m] Inside diameter of pipe
    # Do   [m] Outside diameter of pipe
    # L    [m] Length of pipe
    # A    [m²] Area of pipe
    # V    [m3] Volume of pipe
    # ṁ    [kg/s] Mass flow in heat exchanger
    # H    [W/K] heat conductivity of pipe
    # h    [W/(K.m)] linear  heat conductivity of pipe
    # Q̇    [kJ/hr] 

    # Physics variables
    ρP = 8000         # Density of steel pipe (kg/m3)
    ρw = WaterProperties.density(ustrip(u"°C", T))       # Density of water (kg/m3)
    cp = 0.5 #kJ/(kg/K)
    cw = WaterProperties.specheat(ustrip(u"°C", T)) / 1000 #kJ/(kg/K)

    # Assumptions ----------------------------------------
    tau1 = ρw * pipe1.V / (pipe1.ṁ * cw * ρw * pipe1.A / (cw * ρw * pipe1.A + cp * ρP * 3.14 * (pipe1.Do^2 - pipe1.Di^2) /4)) # Delay in pipe 1
    tau2 = ρw * pipe2.V / (pipe2.ṁ * cw * ρw * pipe2.A / (cw * ρw * pipe2.A + cp * ρP * 3.14 * (pipe2.Do^2 - pipe2.Di^2) /4)) # Delay in pipe 2

    if tau1 > tau2
        R1 = pipe2
        R2 = pipe1
    else
        R1 = pipe1
        R2 = pipe2
    end

    # Identifiy knots
    KO = R1.FromTo[1]
    KA = R1.FromTo[2]
    KB = R2.FromTo[2]

    # Create new links for nodes
    RAFrom = KO
    RATo =  KA
    RALoadsName = R1.LoadsName
    RBFrom = KA
    RBTo =  KB
    RBLoadsName = R2.LoadsName
    # Collapse tree equivalence ----------------------------
    
    # Composite variables
    Cp1 = cp * ρP * 3.14 * (R1.Do^2 - R1.Di^2) /4         # Pipe Spec. heat [kJ/(m.K)]
    Cp2 = cp * ρP * 3.14 * (R2.Do^2 - R2.Di^2) /4         # Pipe Spec. heat [kJ/(m.K)] 
    Cw1 = cw * ρw * R1.A      # Water spec. heat [kJ/(m.K)] 
    Cw2 = cw * ρw * R2.A   # Water spec. heat [kJ/(m.K)
    Φ1 = Cw1 / (Cw1 + Cp1)      # Using heat capacity per meter in [kJ/(m.K)]
    Φ2 = Cw2 / (Cw2 + Cp2)      # Using heat capacity in [kJ/(m.K)]
    α = R2.ṁ / R1.ṁ             # α>0
    γ = (R1.V/R2.V)*α           # 0<γ<1/ψ
    ψ = Φ2 / Φ1                 # ψ>0
    β = 1 + α                   # β>1
  
    # For pipe B
    ΦB = Φ2
    RBDi = R2.Di
    RBDo = R2.Do
    RBL = R2.L * (1 - γ*ψ)
    RBA = R2.A
    RBV = RBL * RBA
    RBṁ =  R2.ṁ
    RBQ̇ = R2.Q̇

    # For pipe A
    ΦA = (Φ1 + α * Φ2) / (1 + α)
    RAA = (β*(1+α*ψ)*R1.A*R2.A) / (R2.A+R1.A*α*α*ψ)
    RADi = 2*sqrt(RAA / 3.14)
    RADo = RADi * sqrt(1+(ρw*cw)/(ρP*cp)*(1-ΦA)/ΦA)
    RAL  = R1.L * (1+ α*α*ψ*R1.A/R2.A)/β
    RAV  = RAL * RAA
    RAṁ  = R1.ṁ + R2.ṁ
    RAQ̇ = R1.Q̇ + R2.Q̇ 

    # Heat losses
    if R2.H/R1.H > α
        RAH = (1+α)*R1.H
        RBH = R2.H - α*R1.H
    else
        RAH = R1.H + γ*ψ*R2.H
        RBH = R2.H * (1-γ*ψ)
    end

    # Wifdth
    k_ins = 0.027 #u"W/(m*°C)"
    RAe = (exp((2*π*k_ins) *RAL / RAH) * RADo - RADo)/2
    RBe = (exp((2*π*k_ins) *RBL / RBH) * RBDo - RBDo)/2

    # Check elements
    if RADi<0
        println("Error on "*string(RADi))
    elseif RADo<0
        println("Error on "*string(RADo))
    elseif RAL<0
        println("Error on "*string(RAL))
    elseif RAV<0
        println("Error on "*string(RAV))
    elseif RAQ̇<0
        println("Error on "*string(RAQ̇))
    elseif RAH<0
        println("Error on "*string(RAH))
    end
    # Check elements
    if RBDi<0
        println("Error on "*string(RBDi))
    elseif RBDo<0
        println("Error on "*string(RBDo))
    elseif RBL<0
        println("Error on "*string(RBL))
    elseif RBV<0
        println("Error on "*string(RBV))
    elseif RBQ̇<0
        println("Error on "*string(RBQ̇))
    elseif RBH<0
        println("Error on "*string(RBH))
    end
        # Update segments
    Topology.Segments[R1.id] = TopologyStruct.Segment(R1.id, RAFrom*"_"*RATo, (RAFrom,RATo), RALoadsName, RAṁ, RADi, RADo, RAL, RAA, RAe, RAV, RAQ̇, RAH)
    Topology.Segments[R2.id] = TopologyStruct.Segment(R2.id, RBFrom*"_"*RBTo, (RBFrom,RBTo), RBLoadsName, RBṁ, RBDi, RBDo, RBL, RBA, RAe, RBV, RBQ̇, RBH)

    return Topology
end


"""
    ReducingSerialDanish(Topology, pipe1, pipe2, T)

Function for reducing branch *R2* on branch *R1* and *R3*. Will result in two equivalent branches as shown on figure.
Using Larsen et al. (2002) method for reducing branches described in [this paper](https://www.sciencedirect.com/science/article/pii/S0196890401000930?via%3Dihub).
This method preserve pipes insulation factor k_ins [W/m*K], total volume of fluid [m3] and total heat losses [W/K], and loads delay.

![Danish method schema](img/DanishMethod.png)

# Arguments
- `Topology`: (*System*) A System struct object of the reference network topology.
- `R1`: (*Segment*) The Segment struct object before *R2*. Segment destination must be *R2* origin.
- `R2`: (*Segment*) The Segment struct object that will be reduced on *R1* and *R3*. 
- `R3`: (*Segment*) The Segment struct object after *R2*. Segment origin must be *R2* destination.
- `T`: (*Float64*) [°C]  Mean temperature of pipes in network. 
# Outputs
- `Topology`: (*System*) A System struct object of network topology after the collapsing algorithm.
"""
function ReducingSerialDanish(Topology, R1, R2, R3, T)

    # Sub-system schemes -----------------------------------------
    # From:
    # --R1-- (K1v) --R2-- (K2v) --R3--
    #          |            |           
    #        <VB1>        <VB2>       
    #          |            |            
    # --R1-- (K1r) --R2-- (K2r) --R3--

    # To:
    # --RA-- (Keqv) --RB--
    #          |                      
    #        <VBeq>               
    #          |                
    # --RA-- (Keqr) --RB-- 
    
    # Get nodes
    K0 = Topology.Nodes[1]
    K1 = Topology.Nodes[1]
    K2 = Topology.Nodes[1]
    K3 = Topology.Nodes[1]

    for node in Topology.Nodes
        if node.name == R1.FromTo[1]
            K0 = node
        elseif node.name == R2.FromTo[1]
            K1 = node
        elseif node.name == R3.FromTo[1]
            K2 = node
        elseif node.name == R3.FromTo[2]
            K3 = node
        end
    end

    # Physics variables --------------------------------------------
    ρP = 8000         # Density of steel pipe (kg/m3)
    ρw = WaterProperties.density(ustrip(u"°C", T))       # Density of water (kg/m3)
    cp = 0.5 #kJ/(kg/K)
    cw = WaterProperties.specheat(ustrip(u"°C", T)) / 1000 #kJ/(kg/K)


    # Build equivalent pipe --------------------------------------
    # Variables
    X = (ρP*cp)/(ρw*cw)
    V1p = 3.1416/4*R1.L*R1.Do*R1.Do - R1.V
    V2p = 3.1416/4*R2.L*R2.Do*R2.Do - R2.V
    V3p = 3.1416/4*R3.L*R3.Do*R3.Do - R3.V
    Φ1 = 1/(1+X*V1p/R1.V)
    Φ2 = 1/(1+X*V2p/R2.V)
    Φ3 = 1/(1+X*V3p/R3.V)
    τ1 = ρw*R1.V/(R1.ṁ*Φ1)
    τ2 = ρw*R2.V/(R2.ṁ*Φ2)
    τ3 = ρw*R3.V/(R3.ṁ*Φ3)

    # Variables for Eq 
    fa = (R2.ṁ - R3.ṁ) / (R1.ṁ - R3.ṁ)
    fb = 1 - fa
    # Because we reduce to 1 node per cluster, and because of max delay (about 30min) being below timestep of 1h, we choose g-factor different.
    gAA = fa*τ2 / (τ1 + fa*τ2)
    gBA = τ3    / (τ3 + fb*τ2)
    RAṁ = R1.ṁ - gAA*(R1.ṁ-R2.ṁ)
    RBṁ = R2.ṁ - gBA*(R2.ṁ-R3.ṁ)

    # Equivalent equations
    RAL = R1.L + fa * R2.L
    RBL = R3.L + fb * R2.L

    ΦA = 1/(1+X*(V1p+fa*V2p)/(R1.V+fa*R2.V))
    ΦB = 1/(1+X*(V3p+fb*V2p)/(R3.V+fb*R2.V))

    RAV = R1.V * (RAṁ*ΦA)/(R1.ṁ*Φ1) + fa*R2.V*(RAṁ*ΦA)/(R2.ṁ*Φ2)
    RBV = R3.V * (RBṁ*ΦB)/(R3.ṁ*Φ3) + fb*R2.V*(RBṁ*ΦB)/(R2.ṁ*Φ2)

    VAp = RAV * (1-ΦA)/(ΦA*X)
    VBp = RBV * (1-ΦB)/(ΦB*X)

    RADi = 2*sqrt(RAV/(3.1416*RAL))
    RBDi = 2*sqrt(RBV/(3.1416*RBL))

    RADo = 2*sqrt((RAV+VAp)/(3.1416*RAL)) 
    RBDo = 2*sqrt((RBV+VBp)/(3.1416*RBL)) 

    RAA = 3.1416* RADi * RADi / 4
    RBA = 3.1416* RBDi * RBDi / 4
    
    RAH = (R1.H + fa*R2.H)
    RBH = (R3.H + fb*R2.H) 

    k_ins = 0.027 #u"W/(m*°C)"
    RAe = (exp((2*π*k_ins) *RAL / RAH) * RADo - RADo)/2
    RBe = (exp((2*π*k_ins) *RBL / RBH) * RBDo - RBDo)/2

    # Build equivalent nodes --------------------------------------

    Keqname = K1.name*"`"
    KeqLoadsName = ["tempEq_"*K2.name*"_"*K1.name] # Name of the loads dataframe in kj/hr [String]
    
    KeqQ̇t = K1.Q̇t * (1 - gAA) + K2.Q̇t * gBA
    K0.Q̇t = K0.Q̇t + K1.Q̇t * gAA
    K3.Q̇t = K3.Q̇t + K2.Q̇t * (1 - gBA)

    RAQ̇ = maximum(KeqQ̇t+K3.Q̇t)
    RBQ̇ = R2.Q̇ - gBA*(R2.Q̇-R3.Q̇)

    RALoadsName =  ["Composite"]
    RBLoadsName =  ["Composite"]

    # Save equivalent ---------------------------------------------
    
    
    RAFrom = R1.FromTo[1]
    RATo   = Keqname
    RBFrom  = Keqname
    RBTo    = R3.FromTo[2]

    Topology.Nodes[K1.id] = TopologyStruct.Node(K1.id, Keqname, KeqLoadsName, KeqQ̇t)
    deleteat!(Topology.Nodes, K2.id) 
    Topology.Segments[R1.id] = TopologyStruct.Segment(R1.id, RAFrom*"_"*RATo, (RAFrom,RATo), RALoadsName, RAṁ, RADi, RADo, RAL, RAA, RAe, RAV, RAQ̇, RAH)
    Topology.Segments[R2.id] = TopologyStruct.Segment(R2.id, RBFrom*"_"*RBTo, (RBFrom,RBTo), RBLoadsName, RBṁ, RBDi, RBDo, RBL, RBA, RBe, RBV, RBQ̇, RBH)
    deleteat!(Topology.Segments, R3.id) 

    for i in 1:length(Topology.Nodes)
        Topology.Nodes[i].id = i
    end
    for i in 1:length(Topology.Segments)
        Topology.Segments[i].id = i
    end
    # Print error values
    if RAV<0
        println("Error negative value for RAV: "*string(RAV))
    end
    if RAL<0
        println("Error negative value for RAL: "*string(RAL))
    end
    if RADi<0
        println("Error negative value for RADi: "*string(RADi))
    end
    if RADo<0
        println("Error negative value for RADo: "*string(RADo))
    end
    if RAṁ<0
        println("Error negative value for RAṁ: "*string(RAṁ))
    end
    if RAH<0
        println("Error negative value for RAH: "*string(RAH))
    end
    if RBV<0
        println("Error negative value for RBV: "*string(RBV))
    end
    if RBL<0
        println("Error negative value for RBL: "*string(RBL))
    end
    if RBDi<0
        println("Error negative value for RBDi: "*string(RBDi))
    end
    if RBDo<0
        println("Error negative value for RBDo: "*string(RBDo))
    end
    if RBṁ<0
        println("Error negative value for RBṁ: "*string(RBṁ))
    end
    if RBH<0
        println("Error negative value for RBH: "*string(RBH))
    end
    if RBṁ>RAṁ
        println("Error negative flowrate for Eq: "*string(RAṁ)*" / "*string(RBṁ))
    end
    return Topology

end

end # Module