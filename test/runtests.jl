using Revise, Hedgehog, Test, Dates, Distributions

include("unit/date_functions.jl")
include("unit/payoff.jl")
include("unit/vol_surface.jl")
include("unit/rate_curve.jl")
include("unit/black_scholes.jl")
include("unit/calibration.jl")
include("unit/binomial_tree.jl")
include("unit/vol_surface.jl")

include("agreement/price_agreement.jl")
include("agreement/greeks_agreement.jl")
include("agreement/montecarlo_black_scholes.jl")
include("agreement/montecarlo_heston.jl")
include("agreement/american_options.jl")