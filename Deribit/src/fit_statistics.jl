# fit_statistics.jl
# Functions for computing and analyzing goodness-of-fit statistics

using Dates
using Statistics
using Printf
using Hedgehog
using DataFrames
using CSV

"""
    FitStatistics

Container for goodness-of-fit metrics for a single validation period.

# Fields
- `name`: Period identifier (e.g., "Calibration", "ΔT=+1h @ 2025-10-21 13:00:00")
- `n_quotes`: Number of option quotes
- `spot`: Spot price
- `reference_date`: Reference date for the market data
- `price_mae`: Mean absolute price error
- `price_rmse`: Root mean squared price error
- `price_max_error`: Maximum absolute price error
- `price_mean_rel_err`: Mean relative price error (%)
- `vol_mae`: Mean absolute vol error (percentage points)
- `vol_rmse`: Root mean squared vol error (percentage points)
- `vol_max_error`: Maximum absolute vol error (percentage points)
- `market_vols`: Vector of market implied vols
- `heston_vols`: Vector of Heston-implied vols
- `market_prices`: Vector of market prices
- `heston_prices`: Vector of Heston prices
- `quotes`: Vector of VolQuote objects
"""
struct FitStatistics
    name::String
    n_quotes::Int
    spot::Float64
    reference_date::DateTime
    
    # Price errors
    price_mae::Float64
    price_rmse::Float64
    price_max_error::Float64
    price_mean_rel_err::Float64
    
    # Vol errors
    vol_mae::Float64
    vol_rmse::Float64
    vol_max_error::Float64
    
    # Raw data
    market_vols::Vector{Float64}
    heston_vols::Vector{Float64}
    market_prices::Vector{Float64}
    heston_prices::Vector{Float64}
    quotes::Vector
end

"""
    compute_fit_statistics(market_surface, calibrated_heston, pricing_method, rate, iv_config; 
                          validation_name="")
    -> FitStatistics

Compute comprehensive goodness-of-fit statistics by comparing Heston model prices 
to market prices, and backing out implied vols.

# Arguments
- `market_surface`: MarketVolSurface with market data
- `calibrated_heston`: HestonInputs with calibrated parameters
- `pricing_method`: Pricing method (e.g., CarrMadan)
- `rate`: Risk-free rate
- `iv_config`: Dict with implied vol solver settings:
  - `"initial_guess"`: Starting vol for solver
  - `"lower_bound"`: Lower bound for vol
  - `"upper_bound"`: Upper bound for vol
- `validation_name`: Name/label for this validation period

# Returns
FitStatistics object with all computed metrics

# Example
```julia
iv_config = Dict("initial_guess" => 0.5, "lower_bound" => 0.05, "upper_bound" => 2.0)
stats = compute_fit_statistics(mkt_surface, heston_inputs, CarrMadan(...), 0.03, iv_config;
                               validation_name="Calibration")
```
"""
function compute_fit_statistics(market_surface, calibrated_heston, pricing_method, 
                                rate, iv_config; validation_name="")
    reference_date = Dates.epochms2datetime(market_surface.reference_date)
    spot = market_surface.spot

    println("  Computing fit statistics on $(length(market_surface.quotes)) options...")

    market_vols = [q.implied_vol for q in market_surface.quotes]
    market_prices = [q.price for q in market_surface.quotes]

    # Heston prices
    heston_prices = [
        solve(PricingProblem(q.payoff, calibrated_heston), pricing_method).price
        for q in market_surface.quotes
    ]

    # Price errors
    price_errors = heston_prices .- market_prices
    abs_price_errors = abs.(price_errors)
    rel_price_errors = abs_price_errors ./ market_prices .* 100

    # Back out implied vols via BS by solving for vol that matches each Heston price
    heston_vols = Float64[]
    for (i, vol_quote) in enumerate(market_surface.quotes)
        try
            dummy_inputs = BlackScholesInputs(reference_date, rate, spot, iv_config["initial_guess"])
            basket = BasketPricingProblem([vol_quote.payoff], dummy_inputs)
            calib = CalibrationProblem(
                basket,
                BlackScholesAnalytic(),
                [VolLens(1,1)],
                [heston_prices[i]],
                [iv_config["initial_guess"]];
                lb=[iv_config["lower_bound"]],
                ub=[iv_config["upper_bound"]]
            )
            push!(heston_vols, solve(calib, RootFinderAlgo()).u)
        catch
            push!(heston_vols, market_vols[i])
        end
    end

    vol_errors = (heston_vols .- market_vols) .* 100
    abs_vol_errors = abs.(vol_errors)

    return FitStatistics(
        validation_name,
        length(market_surface.quotes),
        spot,
        reference_date,
        mean(abs_price_errors),
        sqrt(mean(price_errors.^2)),
        maximum(abs_price_errors),
        mean(rel_price_errors),
        mean(abs_vol_errors),
        sqrt(mean(vol_errors.^2)),
        maximum(abs_vol_errors),
        market_vols,
        heston_vols,
        market_prices,
        heston_prices,
        market_surface.quotes
    )
end

"""
    print_fit_summary(stats::FitStatistics)

Print a formatted summary of fit statistics to stdout.
"""
function print_fit_summary(stats::FitStatistics)
    println("$(stats.name):")
    @printf("  Price RMSE:  \$%.4f\n", stats.price_rmse)
    @printf("  Price MAE:   \$%.4f\n", stats.price_mae)
    @printf("  Price Max:   \$%.4f\n", stats.price_max_error)
    @printf("  Vol RMSE:    %.2f%% points\n", stats.vol_rmse)
    @printf("  Vol MAE:     %.2f%% points\n", stats.vol_mae)
    @printf("  Vol Max Err: %.2f%% points\n", stats.vol_max_error)
end

"""
    print_fit_summary(stats_vec::Vector{FitStatistics})

Print summaries for multiple fit statistics.
"""
function print_fit_summary(stats_vec::Vector{FitStatistics})
    println("\n" * "="^70)
    println("Validation Summary:")
    println("="^70)
    for stats in stats_vec
        println()
        print_fit_summary(stats)
    end
    println("="^70)
end

"""
    save_fit_summary_csv(stats_vec::Vector{FitStatistics}, filepath::String)

Save summary statistics for multiple periods to CSV.

# Arguments
- `stats_vec`: Vector of FitStatistics
- `filepath`: Output CSV path

# CSV Columns
period, n_quotes, spot, price_rmse, price_mae, price_max_error, 
vol_rmse, vol_mae, vol_max_error
"""
function save_fit_summary_csv(stats_vec::Vector{FitStatistics}, filepath::String)
    df = DataFrame(
        period = [s.name for s in stats_vec],
        n_quotes = [s.n_quotes for s in stats_vec],
        spot = [s.spot for s in stats_vec],
        price_rmse = [s.price_rmse for s in stats_vec],
        price_mae = [s.price_mae for s in stats_vec],
        price_max_error = [s.price_max_error for s in stats_vec],
        vol_rmse = [s.vol_rmse for s in stats_vec],
        vol_mae = [s.vol_mae for s in stats_vec],
        vol_max_error = [s.vol_max_error for s in stats_vec]
    )
    CSV.write(filepath, df)
    println("✓ Summary CSV saved to: $filepath")
end

"""
    save_fit_detailed_csv(stats::FitStatistics, filepath::String)

Save detailed per-option statistics to CSV.

# CSV Columns
strike, expiry_date, option_type, market_vol, heston_vol, vol_error,
market_price, heston_price, price_error
"""
function save_fit_detailed_csv(stats::FitStatistics, filepath::String)
    df = DataFrame(
        strike = [q.payoff.strike for q in stats.quotes],
        expiry_date = [Date(Dates.epochms2datetime(q.payoff.expiry)) for q in stats.quotes],
        option_type = [isa(q.payoff.call_put, Call) ? "Call" : "Put" for q in stats.quotes],
        market_vol = stats.market_vols .* 100,
        heston_vol = stats.heston_vols .* 100,
        vol_error = (stats.heston_vols .- stats.market_vols) .* 100,
        market_price = stats.market_prices,
        heston_price = stats.heston_prices,
        price_error = stats.heston_prices .- stats.market_prices
    )
    CSV.write(filepath, df)
    println("✓ Detailed CSV saved to: $filepath")
end

"""
    save_all_detailed_csvs(stats_vec::Vector{FitStatistics}, output_dir::String)

Save detailed CSVs for all periods in stats_vec.
Filenames are based on sanitized period names.
"""
function save_all_detailed_csvs(stats_vec::Vector{FitStatistics}, output_dir::String)
    for stats in stats_vec
        period_name = replace(stats.name, " " => "_", "+" => "plus", ":" => "", "@" => "at")
        filepath = joinpath(output_dir, "detailed_$(period_name).csv")
        save_fit_detailed_csv(stats, filepath)
    end
end