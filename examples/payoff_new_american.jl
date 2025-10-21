# test_american.jl
using Revise, Dates, Hedgehog
using BenchmarkTools

println("="^70)
println("AMERICAN OPTION PRICING - NEW DESIGN")
println("="^70)

# Create American put
am_put = AmericanVanillaOption(100.0, Date(2025, 12, 31), Put())

# Verify it's American
@assert exercise_style(am_put.actions) == AmericanStyle()
@assert am_put.actions isa StoppingRule
@assert am_put.payoff isa VanillaPayoff

# Market data
market = BlackScholesInputs(Date(2025, 1, 1), 0.05, 100.0, 0.3)

# Create pricing problem
prob = PricingProblem(am_put, market)

# Price with binomial tree
method = CoxRossRubinsteinMethod(100)
sol = solve(prob, method)
println("\n✓ American Put Price (new design): ", sol.price)

# Compare with old design
old_am_put = Hedgehog.VanillaOption(
    100.0, 
    Date(2025, 12, 31), 
    Hedgehog.American(), 
    Put(), 
    Hedgehog.Spot()
)
old_prob = PricingProblem(old_am_put, market)
old_sol = solve(old_prob, method)
println("✓ American Put Price (old design): ", old_sol.price)

# Verify they match
@assert isapprox(sol.price, old_sol.price, rtol=1e-10)
println("\n✓ New and old designs produce identical prices!")

# Also test European for comparison
euro_put = VanillaOption(100.0, Date(2025, 12, 31), Put())
euro_prob = PricingProblem(euro_put, market)
euro_sol_bs = solve(euro_prob, BlackScholesAnalytic())
euro_sol_crr = solve(euro_prob, method)

println("\n--- European Put (for comparison) ---")
println("Black-Scholes:  ", euro_sol_bs.price)
println("CRR (100 steps): ", euro_sol_crr.price)
println("American Put:    ", sol.price)
println("\n✓ American ≥ European (early exercise premium): ", 
        sol.price >= euro_sol_bs.price)

# Benchmark
println("\n" * "="^70)
println("PERFORMANCE COMPARISON")
println("="^70)

println("\n📊 American Put - New Design:")
@btime solve($prob, $method)

println("\n📊 American Put - Old Design:")
@btime solve($old_prob, $method)

println("\n📊 European Put (BS) - New Design:")
euro_method = BlackScholesAnalytic()
@btime solve($euro_prob, $euro_method)