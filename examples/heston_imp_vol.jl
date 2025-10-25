# test_heston_iv.jl
using Hedgehog
using Dates
using Plots
using Printf

println("Testing Heston IV Surface Generation")
println("="^70)

# 1) Define Heston parameters
reference_date = DateTime(2020, 7, 1, 0, 0, 0)
spot = 100.0
rate = 0.0
v0 = 0.01      # Initial variance
κ = 1.0        # Mean reversion speed
θ = 0.04       # Long-term variance
σ = 0.4        # Vol of vol
ρ = -0.3       # Correlation

heston_inputs = HestonInputs(reference_date, rate, spot, v0, κ, θ, σ, ρ)

println("\nHeston Parameters:")
@printf("  Spot:  %.2f\n", spot)
@printf("  v0:    %.4f (%.2f%% vol)\n", v0, sqrt(v0)*100)
@printf("  κ:     %.4f\n", κ)
@printf("  θ:     %.4f (%.2f%% vol)\n", θ, sqrt(θ)*100)
@printf("  σ:     %.4f\n", σ)
@printf("  ρ:     %.4f\n", ρ)

# 2) Define grid
maturities = [0.25, 0.5, 0.75, 1.0, 1.5]  # in years
moneyness = range(0.8, 1.2, length=15)
strikes = [spot * m for m in moneyness]

println("\nGrid:")
println("  Maturities (years): ", maturities)
println("  Moneyness range: $(minimum(moneyness)) to $(maximum(moneyness))")
println("  Number of strikes: $(length(strikes))")

# 3) Price options with Heston
pricing_method = CarrMadan(1.5, 128.0, HestonDynamics())

println("\n[1] Pricing calls with Heston...")
prices = Dict()
for T in maturities
    expiry = reference_date + Day(round(Int, T * 365))
    for K in strikes
        payoff = VanillaOption(K, expiry, European(), Call(), Spot())
        prob = PricingProblem(payoff, heston_inputs)
        price = solve(prob, pricing_method).price
        prices[(T, K)] = price
    end
    println("  Completed T=$(T)y")
end

# 4) Back out implied vols
println("\n[2] Extracting implied volatilities...")

function implied_vol_from_price(K, expiry, price, spot, rate, ig=0.5)
    bs_inputs = BlackScholesInputs(reference_date, rate, spot, ig)
    payoff = VanillaOption(K, expiry, European(), Call(), Spot())
    
    basket = BasketPricingProblem([payoff], bs_inputs)
    calib = CalibrationProblem(
        basket,
        BlackScholesAnalytic(),
        [VolLens(1,1)],
        [price],
        [ig];
        lb=[0.01],
        ub=[3.0]
    )
    
    try
        res = solve(calib, RootFinderAlgo())
        return res.u isa AbstractVector ? res.u[1] : res.u
    catch e
        @warn "IV inversion failed for K=$K, expiry=$expiry"
        return NaN
    end
end

# Build IV matrix: rows = maturities, cols = strikes
IV_matrix = zeros(length(maturities), length(strikes))
for (i, T) in enumerate(maturities)
    expiry = reference_date + Day(round(Int, T * 365))
    for (j, K) in enumerate(strikes)
        price = prices[(T, K)]
        iv = implied_vol_from_price(K, expiry, price, spot, rate)
        IV_matrix[i, j] = iv * 100  # Convert to percentage
    end
    println("  Completed T=$(T)y")
end

# 5) Plot 2D slices
println("\n[3] Creating 2D slice plots...")

plots_array = []
for (i, T) in enumerate(maturities)
    log_mon = log.(strikes ./ spot)
    iv_slice = IV_matrix[i, :]
    
    p = plot(log_mon, iv_slice,
             xlabel="Log-moneyness",
             ylabel="Implied Vol (%)",
             title="T = $(T)y",
             marker=:circle,
             markersize=4,
             linewidth=2,
             legend=false,
             color=:blue)
    
    vline!(p, [0.0], color=:gray, linestyle=:dot, alpha=0.5)
    
    push!(plots_array, p)
end

combined_slices = plot(plots_array..., 
                       layout=(2, 3),
                       size=(1200, 800),
                       plot_title="Heston Implied Volatility Smiles")

savefig(combined_slices, "test_heston_iv_slices.png")
println("✓ 2D slices saved to: test_heston_iv_slices.png")

# 6) Plot 3D surface
println("\n[4] Creating 3D surface plot...")

log_mon = log.(strikes ./ spot)

p3d = surface(log_mon, maturities, IV_matrix,
              xlabel="Log-moneyness",
              ylabel="Maturity (years)",
              zlabel="Implied Vol (%)",
              title="Heston Implied Volatility Surface",
              camera=(30, 30),
              color=:viridis,
              colorbar=true,
              size=(800, 600))

# Add scatter points at grid locations
scatter3d!(p3d, 
          repeat(log_mon, outer=length(maturities)),
          repeat(maturities, inner=length(strikes)),
          vec(IV_matrix'),
          markersize=2,
          markercolor=:red,
          label="Grid points",
          alpha=0.5)

savefig(p3d, "test_heston_iv_3d.png")
println("✓ 3D surface saved to: test_heston_iv_3d.png")

println("\n" * "="^70)
println("Test complete!")
println("\nSummary Statistics:")
@printf("  Min IV:  %.2f%%\n", minimum(IV_matrix))
@printf("  Max IV:  %.2f%%\n", maximum(IV_matrix))
@printf("  Mean IV: %.2f%%\n", mean(IV_matrix))