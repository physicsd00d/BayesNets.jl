module BayesNets

export BayesNet, addEdge!, removeEdge!, addEdges!, CPD, CPDs, prob, setCPD!, pdf, rand, randBernoulliDict, randDiscreteDict, table, domain, Assignment, *, sumout, normalize, select, randTable, NodeName, consistent, estimate, randTableWeighted, estimateConvergence, isValid
export Domain, BinaryDomain, DiscreteDomain, RealDomain, domain, cpd, parents

import Graphs: GenericGraph, simple_graph, Edge, add_edge!, topological_sort_by_dfs, in_edges, source, in_neighbors, source, target, AbstractGraph, test_cyclic_by_dfs
import TikzGraphs: plot
import Base: rand, select
import DataFrames: DataFrame, groupby, array, isna

typealias DAG GenericGraph{Int64,Edge{Int64},Range1{Int64},Array{Edge{Int64},1},Array{Array{Edge{Int64},1},1}}

typealias NodeName Symbol

typealias Assignment Dict

Base.zero(::Any) = ""

function consistent(a::Assignment, b::Assignment)
    commonKeys = intersect(keys(a), keys(b))
    all([a[k] == b[k] for k in commonKeys])
end

include("cpds.jl")

typealias CPD CPDs.CPD

DAG(n) = simple_graph(n)

abstract Domain

type DiscreteDomain <: Domain
  elements::Vector
end

type ContinuousDomain <: Domain
  lower::Real
  upper::Real
end

BinaryDomain() = DiscreteDomain([false, true])

RealDomain() = ContinuousDomain(-Inf, Inf)

type BayesNet
  dag::DAG
  cpds::Vector{CPD}
  index::Dict{NodeName,Int}
  names::Vector{NodeName}
  domains::Vector{Domain}

  function BayesNet(names::Vector{NodeName})
    n = length(names)
    index = [names[i]=>i for i = 1:n]
    cpds = CPD[CPDs.Bernoulli() for i = 1:n]
    domains = Domain[BinaryDomain() for i = 1:n] # default to binary domain
    new(simple_graph(length(names)), cpds, index, names, domains)
  end

  function BayesNet{GT<:AbstractGraph}(incomingGraph::GT, incomingNames::Vector{NodeName} = Vector{NodeName}[])
    # Having generated a graph, turn that into a BayesNet

    n = length(incomingGraph.vertices)
    names = Vector{Symbol}[]

    # If the node names were given, use them, otherwise make them generic
    if length(incomingNames) == n
      # Do nothing, just use incomingNames
      names = incomingNames
    elseif length(incomingNames) == 0
      # User didn't pass in any names, make some generic names instead
      # For some reason, you can't have the first character be a number for a symbol.  Make it N for nodes.
      names = [symbol("N$curName") for curName in incomingGraph.vertices]
    else
      line1 = "ERROR: You tried to generate a BayesNet from an AbstractGraph\n"
      line2 = "       You passed in $(length(incomingNames)) but there are $(n) verticies in the Graph"
      error(line1 * line2)
    end

    index = [names[i]=>i for i = 1:n]
    cpds = CPD[CPDs.Bernoulli() for i = 1:n]
    domains = Domain[BinaryDomain() for i = 1:n] # default to binary domain

    # Flatten out the edges into a single array
    edgeList = Array(Edge{Int64},0)
    for thisList in incomingGraph.inclist
      for thisEdge in thisList
        push!(edgeList, thisEdge)
      end
    end

    # Make the empty BayesNet
    this = new(simple_graph(length(names)), cpds, index, names, domains)

    # Populate it with the info from the incoming Graph
    this.dag.finclist = incomingGraph.inclist   # I'm not sure if BayesNet even uses this field
    this.dag.binclist = incomingGraph.inclist   # I'm not sure if BayesNet even uses this field
    this.dag.edges    = edgeList                # This one is important!

    # Cover your @$$
    println("BayesNet: You just created me from a Graph.  I did ZERO error checking to make sure you passed a valid DAG.")
    println("          It's also up to you to fill in the conditional probabilities.")

    # Return the object
    this
  end
end

domain(b::BayesNet, name::NodeName) = b.domains[b.index[name]]

cpd(b::BayesNet, name::NodeName) = b.cpds[b.index[name]]

function parents(b::BayesNet, name::NodeName)
  i = b.index[name]
  NodeName[b.names[j] for j in in_neighbors(i, b.dag)]
end

function isValid(b::BayesNet)
  !test_cyclic_by_dfs(b.dag)
end

function addEdge!(bn::BayesNet, sourceNode::NodeName, destNode::NodeName)
  i = bn.index[sourceNode]
  j = bn.index[destNode]
  add_edge!(bn.dag, i, j)
  bn
end

function removeEdge!(bn::BayesNet, sourceNode::NodeName, destNode::NodeName)
  # it would be nice to use a more efficient implementation
  # see discussion here: https://github.com/JuliaLang/Graphs.jl/issues/73
  i = bn.index[sourceNode]
  j = bn.index[destNode]
  newDAG = simple_graph(length(bn.names))
  for edge in bn.dag.edges
    u = source(edge)
    v = target(edge)
    if u != i || v != j
      add_edge!(newDAG, u, v)
    end
  end
  bn.dag = newDAG
  bn
end

function addEdges!(bn::BayesNet, pairs)
  for p in pairs
    addEdge!(bn, p[1], p[2])
  end
  bn
end

function setCPD!(bn::BayesNet, name::NodeName, cpd::CPD)
  i = bn.index[name]
  bn.cpds[i] = cpd
  bn.domains[i] = domain(cpd)
  nothing
end

function prob(bn::BayesNet, assignment::Assignment)
  prod([pdf(bn.cpds[i], assignment)(assignment[bn.names[i]]) for i = 1:length(bn.names)])
end

include("sampling.jl")


Base.mimewritable(::MIME"image/svg+xml", b::BayesNet) = true

Base.mimewritable(::MIME"text/html", dfs::Vector{DataFrame}) = true

function Base.writemime(f::IO, a::MIME"image/svg+xml", b::BayesNet)
  Base.writemime(f, a, plot(b.dag, ASCIIString[string(s) for s in b.names]))
end

function Base.writemime(io::IO, a::MIME"text/html", dfs::Vector{DataFrame})
  for df in dfs
    writemime(io, a, df)
  end
end

include("ndgrid.jl")

function table(bn::BayesNet, name::NodeName)
  edges = in_edges(bn.index[name], bn.dag)
  names = [bn.names[source(e, bn.dag)] for e in edges]
  names = [names, name]
  c = cpd(bn, name)
  d = DataFrame()
  if length(edges) > 0
    A = ndgrid([domain(bn, name).elements for name in names]...)
    i = 1
    for name in names
      d[name] = A[i][:]
      i = i + 1
    end
  else
    d[name] = domain(bn, name).elements
  end
  p = ones(size(d,1))
  for i = 1:size(d,1)
    ownValue = d[i,length(names)]
    a = [names[j]=>d[i,j] for j = 1:(length(names)-1)]
    p[i] = pdf(c, a)(ownValue)
  end
  d[:p] = p
  d
end

table(bn::BayesNet, name::NodeName, a::Assignment) = select(table(bn, name), a)

function *(df1::DataFrame, df2::DataFrame)
  onnames = setdiff(intersect(names(df1), names(df2)), [:p])
  finalnames = vcat(setdiff(union(names(df1), names(df2)), [:p]), :p)
  if isempty(onnames)
    j = join(df1, df2, kind=:cross)
    j[:,:p] .*= j[:,:p_1]
    return j[:,finalnames]
  else
    j = join(df1, df2, on=onnames, kind=:outer)
    j[:,:p] .*= j[:,:p_1]
    return j[:,finalnames]
  end
end

# TODO: this currently only supports binary valued variables
function sumout(a::DataFrame, v::Symbol)
  @assert issubset(unique(a[:,v]), [false, true])
  remainingvars = setdiff(names(a), [v, :p])
  g = groupby(a, v)
  if length(g) == 1
    return a[:,vcat(remainingvars, :p)]
  end
  j = join(g..., on=remainingvars)
  j[:,:p] += j[:,:p_1]
  j[:,vcat(remainingvars, :p)]
end

function sumout(a::DataFrame, v::Vector{Symbol})
  if isempty(v)
    return a
  else
    sumout(sumout(a, v[1]), v[2:end])
  end
end

function normalize(a::DataFrame)
  a[:,:p] /= sum(a[:,:p])
  a
end

function select(t::DataFrame, a::Assignment)
    commonNames = intersect(names(t), keys(a))
    mask = bool(ones(size(t,1)))
    for s in commonNames
        mask &= t[s] .== a[s]
    end
    t[mask, :]
end

function estimate(df::DataFrame)
    n = size(df, 1)
    w = ones(n)
    t = df
    if haskey(df, :p)
        t = df[:, names(t) .!= :p]
        w = df[:p]
    end
    # unique samples
    tu = unique(t)
    # add column with probabilities of unique samples
    tu[:p] = Float64[sum(w[Bool[tu[j,:] == t[i,:] for i = 1:size(t,1)]]) for j = 1:size(tu,1)]
    tu[:p] /= sum(tu[:p])
    tu
end

function estimateConvergence(df::DataFrame, a::Assignment)
    n = size(df, 1)
    p = zeros(n)
    w = ones(n)
    if haskey(df, :p)
        w = df[:p]
    end
    dfindex = find([haskey(a, n) for n in names(df)])
    dfvalues = [a[n] for n in names(df)[dfindex]]'
    cumWeight = 0.
    cumTotalWeight = 0.
    for i = 1:n
        if array(df[i, dfindex]) == dfvalues
            cumWeight += w[i]
        end
        cumTotalWeight += w[i]
        p[i] = cumWeight / cumTotalWeight
    end
    p
end

include("learning.jl")

end # module
