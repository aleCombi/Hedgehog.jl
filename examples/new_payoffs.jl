using Revise, Dates, Hedgehog
using BenchmarkTools

# Create European call (new design)
opt = VanillaOption(100.0, Date(2025, 12, 31), Call())

# Verify it's European (correct way)
@assert exercise_style(opt.actions) == EuropeanStyle()
@assert opt.actions isa NoAction
@assert opt.payoff isa VanillaPayoff

# Create pricing problem
market = BlackScholesInputs(Date(2025, 1, 1), 0.05, 100.0, 0.2)
prob = PricingProblem(opt, market)

# Verify problem structure
@assert prob.payoff.actions isa NoAction
@assert prob.payoff.payoff isa VanillaPayoff

# Price it with new design
sol = solve(prob, BlackScholesAnalytic())
println("New design price: ", sol.price)
method =  BlackScholesAnalytic()
# Compare with old design
old_opt = Hedgehog.VanillaOption(100.0, Date(2025, 12, 31), Hedgehog.European(), Call(), Hedgehog.Spot())
old_prob = PricingProblem(old_opt, market)
old_sol = solve(old_prob, method)
println("Old design price: ", old_sol.price)

# They should match (within numerical tolerance)
@assert isapprox(sol.price, old_sol.price, rtol=1e-10)
println("✓ New and old designs produce identical prices")

# Test payoff evaluation directly
stat = TerminalValue(110.0)
intrinsic = evaluate(opt.payoff, stat)
@assert intrinsic == 10.0

println("\n" * "="^70)
println("PERFORMANCE COMPARISON")
println("="^70)

# Benchmark old design
println("\n📊 Old Design (VanillaOption):")
@btime solve($old_prob, $method) setup=(method=BlackScholesAnalytic())

# Benchmark new design
println("\n📊 New Design (GenericContract):")
@btime solve($prob, $method) setup=(method=BlackScholesAnalytic())

println("\n" * "="^70)
println("Type Stability Check")
println("="^70)

println("\n🔍 New Design:")
@code_warntype solve(prob, BlackScholesAnalytic())

println("\n🔍 Old Design:")
@code_warntype solve(old_prob, BlackScholesAnalytic())