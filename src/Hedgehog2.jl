module Hedgehog2

using DifferentialEquations, ForwardDiff, Distributions, Accessors, Dates

if false 
    include("../examples/includer.jl")
end

if false
    include("../test/runtests.jl")
end

# payoffs
include("payoffs/payoffs.jl")

# market inputs
include("market_inputs/market_inputs.jl")
include("market_inputs/vol_surface.jl")

# pricing methods
include("pricing_methods/pricing_methods.jl")
include("pricing_methods/black_scholes.jl")
include("pricing_methods/cox_ross_rubinstein.jl")
include("pricing_methods/montecarlo.jl")
include("pricing_methods/carr_madan.jl")
include("pricing_methods/least_squares_montecarlo.jl")

# sensitivities

# distributions
include("distributions/heston.jl")
include("distributions/sample_from_cf.jl")
include("solutions/pricing_solutions.jl")

end