# visualization.jl
# Plotting functions for fit quality and mispricing analysis

using Plots
using Statistics
using Printf

include("fit_statistics.jl")
include("mispricing.jl")

"""
    plot_vol_rmse_over_time(stats_vec::Vector{FitStatistics}; kwargs...)
    -> Plots.Plot

Plot vol RMSE progression over validation periods.

# Arguments
- `stats_vec`: Vector of FitStatistics
- `kwargs...`: Additional plot keyword arguments

# Returns
Plots.Plot object
"""
function plot_vol_rmse_over_time(stats_vec::Vector{FitStatistics}; kwargs...)
    p = plot(
        1:length(stats_vec),
        [s.vol_rmse for s in stats_vec];
        xlabel = "Validation Period",
        ylabel = "Vol RMSE (% points)",
        title = "Model Performance Over Time",
        marker = :circle,
        markersize = 6,
        linewidth = 2,
        legend = false,
        xticks = (1:length(stats_vec), [s.name for s in stats_vec]),
        xrotation = 45,
        kwargs...
    )
    return p
end

"""
    plot_vol_error_histogram(stats::FitStatistics; kwargs...)
    -> Plots.Plot

Plot histogram of vol errors for a single period.

# Arguments
- `stats`: FitStatistics for one period
- `kwargs...`: Additional plot keyword arguments

# Returns
Plots.Plot object
"""
function plot_vol_error_histogram(stats::FitStatistics; kwargs...)
    vol_errors = (stats.heston_vols .- stats.market_vols) .* 100
    
    p = histogram(
        vol_errors;
        xlabel = "Vol Error (% points)",
        ylabel = "Frequency",
        title = "$(stats.name): Vol Error Distribution",
        legend = false,
        bins = 20,
        kwargs...
    )
    return p
end

"""
    plot_market_vs_model_scatter(stats::FitStatistics; kwargs...)
    -> Plots.Plot

Scatter plot of market vs model implied vols.

# Arguments
- `stats`: FitStatistics for one period
- `kwargs...`: Additional plot keyword arguments

# Returns
Plots.Plot object
"""
function plot_market_vs_model_scatter(stats::FitStatistics; kwargs...)
    p = scatter(
        stats.market_vols .* 100,
        stats.heston_vols .* 100;
        xlabel = "Market Vol (%)",
        ylabel = "Heston Vol (%)",
        title = "$(stats.name): Market vs Heston",
        legend = false,
        markersize = 4,
        alpha = 0.6,
        kwargs...
    )
    
    # Add perfect fit line
    vmin = min(minimum(stats.market_vols), minimum(stats.heston_vols)) * 100
    vmax = max(maximum(stats.market_vols), maximum(stats.heston_vols)) * 100
    plot!(p, [vmin, vmax], [vmin, vmax]; linestyle=:dash, color=:red, label="Perfect fit")
    
    return p
end

"""
    plot_rmse_comparison_bar(stats_vec::Vector{FitStatistics}; kwargs...)
    -> Plots.Plot

Bar chart comparing vol RMSE and price RMSE across periods.

# Arguments
- `stats_vec`: Vector of FitStatistics
- `kwargs...`: Additional plot keyword arguments

# Returns
Plots.Plot object
"""
function plot_rmse_comparison_bar(stats_vec::Vector{FitStatistics}; kwargs...)
    names = [s.name for s in stats_vec]
    vol_rmse = [s.vol_rmse for s in stats_vec]
    price_rmse = [s.price_rmse for s in stats_vec]
    
    p = bar(
        names,
        [vol_rmse price_rmse];
        xlabel = "Validation Period",
        ylabel = "RMSE",
        title = "Vol RMSE vs Price RMSE",
        label = ["Vol RMSE (% pts)" "Price RMSE (\$)"],
        xrotation = 45,
        bar_width = 0.8,
        legend = :topright,
        kwargs...
    )
    return p
end

"""
    plot_validation_summary(stats_vec::Vector{FitStatistics}; size=(1400, 1200), kwargs...)
    -> Plots.Plot

Create 2x2 combined plot with validation summary.

Includes:
- Top-left: Vol RMSE over time
- Top-right: Vol error histogram (calibration period)
- Bottom-left: Market vs model scatter (calibration period)
- Bottom-right: RMSE comparison bar chart

# Arguments
- `stats_vec`: Vector of FitStatistics (first should be calibration)
- `size`: Plot size tuple (width, height)
- `kwargs...`: Additional plot keyword arguments

# Returns
Combined Plots.Plot object
"""
function plot_validation_summary(stats_vec::Vector{FitStatistics}; size=(1400, 1200), kwargs...)
    calib_stats = stats_vec[1]
    
    p1 = plot_vol_rmse_over_time(stats_vec)
    p2 = plot_vol_error_histogram(calib_stats)
    p3 = plot_market_vs_model_scatter(calib_stats)
    p4 = plot_rmse_comparison_bar(stats_vec)
    
    combined = plot(p1, p2, p3, p4; layout=(2, 2), size=size, kwargs...)
    return combined
end

"""
    save_validation_plots(stats_vec::Vector{FitStatistics}, filepath::String; 
                         size=(1400, 1200))

Create and save validation summary plots.

# Arguments
- `stats_vec`: Vector of FitStatistics
- `filepath`: Output file path (e.g., "validation_results.png")
- `size`: Plot size tuple
"""
function save_validation_plots(stats_vec::Vector{FitStatistics}, filepath::String; 
                              size=(1400, 1200))
    p = plot_validation_summary(stats_vec; size=size)
    savefig(p, filepath)
    println("✓ Validation plots saved to: $filepath")
end

"""
    plot_mispricing_heatmap(records::Vector{MispricingRecord}, field::Symbol; 
                           title="", clabel="", kwargs...)
    -> Plots.Plot

Create heatmap of market - model differences.

# Arguments
- `records`: Vector of MispricingRecord
- `field`: Field to plot (:vol_diff or :price_diff)
- `title`: Plot title
- `clabel`: Colorbar label
- `kwargs...`: Additional plot keyword arguments

# Returns
Plots.Plot object

# Note
For field:
- :vol_diff plots market_vol - model_vol (percentage points)
- :price_diff plots market_price - model_price (currency units)
"""
function plot_mispricing_heatmap(records::Vector{MispricingRecord}, field::Symbol; 
                                title="", clabel="", kwargs...)
    # Extract unique strikes and expiries
    strikes = sort(unique([r.strike for r in records]))
    expiries = sort(unique([r.expiry_date for r in records]))
    
    # Create index mappings
    ix_s = Dict(s => j for (j, s) in enumerate(strikes))
    ix_e = Dict(e => i for (i, e) in enumerate(expiries))
    
    # Initialize matrix with NaN
    Z = fill(NaN, length(expiries), length(strikes))
    
    # Fill matrix
    for r in records
        i = ix_e[r.expiry_date]
        j = ix_s[r.strike]
        
        if field == :vol_diff
            Z[i, j] = r.market_vol - r.model_vol
        elseif field == :price_diff
            Z[i, j] = r.market_price - r.model_price
        end
    end
    
    # Symmetric color limits
    zmax = maximum(abs, filter(!isnan, vec(Z)))
    
    # Y-axis labels (dates)
    ylabels = string.(expiries)
    
    p = heatmap(
        strikes, ylabels, Z;
        xlabel = "Strike",
        ylabel = "Expiry (date)",
        title = title,
        color = cgrad(:RdBu, rev=true),
        clims = (-zmax, zmax),
        colorbar_title = clabel,
        framestyle = :box,
        kwargs...
    )
    
    return p
end

"""
    plot_mispricing_heatmaps(records::Vector{MispricingRecord}; size=(1400, 600), kwargs...)
    -> Plots.Plot

Create side-by-side heatmaps for vol and price differences.

# Arguments
- `records`: Vector of MispricingRecord
- `size`: Plot size tuple
- `kwargs...`: Additional plot keyword arguments

# Returns
Combined Plots.Plot object with 1x2 layout
"""
function plot_mispricing_heatmaps(records::Vector{MispricingRecord}; size=(1400, 600), kwargs...)
    p_vol = plot_mispricing_heatmap(
        records, :vol_diff;
        title = "Market − Model Vol (percentage points)",
        clabel = "pp"
    )
    
    p_price = plot_mispricing_heatmap(
        records, :price_diff;
        title = "Market − Model Price (currency units)",
        clabel = "units"
    )
    
    combined = plot(p_vol, p_price; layout=(1, 2), size=size, kwargs...)
    return combined
end

"""
    save_mispricing_heatmaps(records::Vector{MispricingRecord}, output_dir::String; 
                            size=(1400, 600))

Create and save mispricing heatmaps.

Creates two files:
- heatmap_vol_market_minus_model.png
- heatmap_price_market_minus_model.png

# Arguments
- `records`: Vector of MispricingRecord
- `output_dir`: Output directory
- `size`: Individual plot size
"""
function save_mispricing_heatmaps(records::Vector{MispricingRecord}, output_dir::String; 
                                 size=(1400, 600))
    p_vol = plot_mispricing_heatmap(
        records, :vol_diff;
        title = "Market − Model Vol (percentage points)",
        clabel = "pp"
    )
    
    p_price = plot_mispricing_heatmap(
        records, :price_diff;
        title = "Market − Model Price (currency units)",
        clabel = "units"
    )
    
    savefig(p_vol, joinpath(output_dir, "heatmap_vol_market_minus_model.png"))
    savefig(p_price, joinpath(output_dir, "heatmap_price_market_minus_model.png"))
    
    println("✓ Vol heatmap saved to:   $(joinpath(output_dir, "heatmap_vol_market_minus_model.png"))")
    println("✓ Price heatmap saved to: $(joinpath(output_dir, "heatmap_price_market_minus_model.png"))")
end