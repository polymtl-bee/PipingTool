# Presentation of PipingTool

| Name        | PipingTool   |
| ----------- | ------------ |
| Version     | 3.0          |
| Authors     | MEUNIER G., KUMMERT M. |
| Licence     | MIT          |
| Last update | October 2026 |
| Documentation | [Wiki](https://polymtl-bee.github.io/PipingTool/dev/) |

> A tool for sizing and aggregating pipes in thermal networks for three different topologies.

### 1.1 Overview

PipingTool employs a network formalism inspired by directed graph theory and uses CSV files containing buildings/units load data to size all pipes for three levels of topological accuracy. Following figure provides an overview of the methodology used by this tool. 

![Overview of method](src/img/PipingTooldrawioENG.png)

This package have built-in functions for doing  
1. Defining the network using built-in functions based on graph theory.
2. Selecting pipes from a database [^1] that satisfy pressure loss constraints (this yields the sizing data for the network’s detailed topology).
3. Agregating network using ***simplification method*** based on the calculation of an equivalent node and segment that preserves the sum of loads, pressure drops, and fluid volume.
4. Agregating network using ***reduction method*** based on two well-known algorithms for network aggregation: the tree-collapsing algorithm and the Danish method algorithm (Well described by Larsen H. et al[^2]). 
5. Visualization of network topologies.
6. Build loads for each network clusters
7. Export results for pipe characteristics and cluster loads as CSV files.

See ![Documentation](https://polymtl-bee.github.io/PipingTool/dev/documentation/) section for methodological details and code documentation.

### 1.2 Example of network

The following figure shows an exemple of a real network and its two equivalent network for the reduced method and the simplified method proposed in PipingTool.

![Example NetworkComparison](src/img/NetworkComparison.png)

See ![Example](https://polymtl-bee.github.io/PipingTool/dev/example/) section for a step-by-step tutorial on how to use the package for this example network.

### 1.3 Table of content

```@contents
```

[^1]: Nussbaumer et al., Handbook on Planning of District Heating Networks.
[^2]: Larsen et al., « Aggregated dynamic simulation model of district heating networks ».
