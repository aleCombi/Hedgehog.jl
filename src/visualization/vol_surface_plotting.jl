using Plots, Dates

"""
    plot_vol_2d_by_expiry(surface::MarketVolSurface;
                          field=:mid_iv,
                          show_bid_ask=false,
                          max_expiries=typemax(Int),
                          title="Volatility Slices by Expiry",
                          separate_subplots=false,
                          subplot_layout=nothing)

Create volatility smile plots for multiple expiries. Returns a plot object without displaying.

# Arguments
- `field`: :mid_iv, :bid_iv, :ask_iv, :mid_price, :bid_price, :ask_price, :all (mid+bid+ask IVs), or :all_price (mid+bid+ask prices)
- `show_bid_ask`: if true and `field` is a :mid_* value, also draws bid/ask as dashed lines
- `max_expiries`: limit the number of expiries plotted (useful on very dense surfaces)
- `title`: Plot title (or vector of titles if separate_subplots=true)
- `separate_subplots`: If true, each expiry gets its own subplot
- `subplot_layout`: Tuple like (rows, cols) for subplot layout. If nothing, auto-determined.

# Returns
- `p::Plots.Plot` - Plot object. Use `display(p)` or `plot(p)` to show it, or save with `savefig(p, "file.png")`

# Examples
```julia
# Plot mid IVs
p = plot_vol_2d_by_expiry(surface; field=:mid_iv)

# Plot mid prices
p = plot_vol_2d_by_expiry(surface; field=:mid_price)

# Plot all three IVs together
p = plot_vol_2d_by_expiry(surface; field=:all)

# Plot all three prices together
p = plot_vol_2d_by_expiry(surface; field=:all_price)

# Display it when ready
display(p)

# Or save directly
savefig(p, "vol_surface.png")
```
"""
function plot_vol_2d_by_expiry(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    max_expiries::Int = typemax(Int),
    title::Union{String, Vector{String}} = "Volatility Slices by Expiry",
    separate_subplots::Bool = false,
    subplot_layout::Union{Nothing, Tuple{Int,Int}} = nothing
)
    # determine IV vs price
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv, :all]
    is_price = field in [:mid_price, :bid_price, :ask_price, :all_price]
    ylabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"

    # Handle :all and :all_price fields - plot mid, bid, ask separately
    plot_all_three = (field == :all || field == :all_price)
    if plot_all_three
        show_bid_ask = false  # We'll plot them separately, not as bands
        if field == :all
            field_list = [:mid_iv, :bid_iv, :ask_iv]
        else  # :all_price
            field_list = [:mid_price, :bid_price, :ask_price]
        end
        labels_suffix = ["Mid", "Bid", "Ask"]
    else
        field_list = [field]
        labels_suffix = [""]
        # if mid_* and show_bid_ask, map corresponding bid/ask fields
        bid_field = is_iv ? :bid_iv : (field == :mid_price ? :bid_price : field)
        ask_field = is_iv ? :ask_iv : (field == :mid_price ? :ask_price : field)
    end

    # group by expiry
    groups = Dict{Int, Vector{VolQuote}}()
    for q in surface.quotes
        push!(get!(groups, q.payoff.expiry, VolQuote[]), q)
    end

    # order and cap expiries
    expiries = sort(collect(keys(groups)))
    if !isempty(expiries)
        expiries = expiries[1:min(max_expiries, length(expiries))]
    end

    # Handle separate subplots
    if separate_subplots
        n_plots = length(expiries)
        
        # Determine layout
        if isnothing(subplot_layout)
            # Auto-determine: prefer wider layouts
            cols = min(3, n_plots)
            rows = ceil(Int, n_plots / cols)
            layout = (rows, cols)
        else
            layout = subplot_layout
        end
        
        # Create subplot titles
        if title isa String
            subplot_titles = [
                "$(title) - $(Dates.format(Dates.epochms2datetime(e), "yyyy-mm-dd"))"
                for e in expiries
            ]
        else
            subplot_titles = title
        end
        
        # Create figure with subplots
        p = plot(layout=layout, size=(400*layout[2], 300*layout[1]))
        
        for (idx, e) in enumerate(expiries)
            qs = sort(groups[e], by = q -> q.payoff.strike)
            strikes = [q.payoff.strike for q in qs]
            
            for (fld, lbl_suffix) in zip(field_list, labels_suffix)
                vals = if is_iv
                    [getfield(q, fld) * 100 for q in qs]
                else
                    [getfield(q, fld) for q in qs]
                end
                ok = .!isnan.(vals)
                
                label = plot_all_three ? lbl_suffix : ""
                
                plot!(p, strikes[ok], vals[ok];
                      subplot=idx, label=label, marker=:circle, linewidth=2,
                      xlabel="Strike", ylabel=ylabel, title=subplot_titles[idx])
            end
        end
        
        return p
    end

    # Single plot with all expiries
    p = plot(xlabel="Strike", ylabel=ylabel, title=title, legend=:best)

    for e in expiries
        qs = sort(groups[e], by = q -> q.payoff.strike)
        strikes = [q.payoff.strike for q in qs]

        expiry_label = Dates.format(Dates.epochms2datetime(e), "yyyy-mm-dd")

        # Plot all fields (mid only, or mid+bid+ask if :all)
        for (fld, lbl_suffix) in zip(field_list, labels_suffix)
            vals = if is_iv
                [getfield(q, fld) * 100 for q in qs]
            else
                [getfield(q, fld) for q in qs]
            end
            ok = .!isnan.(vals)

            label = plot_all_three ? "$(expiry_label) $(lbl_suffix)" : expiry_label
            plot!(p, strikes[ok], vals[ok]; label, marker=:circle, linewidth=2)
        end

        # optional bid/ask bands (same color, dashed, unlabeled) - only for non-:all mode
        if show_bid_ask && !plot_all_three && (field == :mid_iv || field == :mid_price)
            bids = is_iv ? [q.bid_iv * 100 for q in qs] : [q.bid_price for q in qs]
            asks = is_iv ? [q.ask_iv * 100 for q in qs] : [q.ask_price for q in qs]
            okb = .!isnan.(bids); oka = .!isnan.(asks)

            # match the latest series color
            col = p.series_list[end][:linecolor]
            if any(okb)
                plot!(p, strikes[okb], bids[okb]; label="", linestyle=:dash, color=col, alpha=0.5, linewidth=1)
            end
            if any(oka)
                plot!(p, strikes[oka], asks[oka]; label="", linestyle=:dash, color=col, alpha=0.5, linewidth=1)
            end
        end
    end

    return p
end


"""
    plot_vol_surface_3d(surface::MarketVolSurface;
                        field=:mid_iv,
                        title="Volatility Surface 3D",
                        show_points=true,
                        show_all=false)

Create 3D scatter/surface plot over (Strike, Time to Maturity). Returns plot object without displaying.

# Arguments
- `field`: :mid_iv, :bid_iv, :ask_iv, :mid_price, :bid_price, :ask_price, :all (mid+bid+ask IVs), or :all_price (mid+bid+ask prices)
- `title`: Plot title (or titles if show_all=true and title is a vector)
- `show_points`: If true, plot as scatter points; if false, plot as wireframe
- `show_all`: If true and field=:all or :all_price, creates 3 separate subplots for mid/bid/ask

# Returns
- `p::Plots.Plot` - Plot object. Use `display(p)` to show it, or save with `savefig(p, "file.png")`

# Examples
```julia
# 3D plot of mid IVs
p = plot_vol_surface_3d(surface; field=:mid_iv, show_points=false)

# 3D plot of mid prices
p = plot_vol_surface_3d(surface; field=:mid_price)

# All three IVs in one 3D plot
p = plot_vol_surface_3d(surface; field=:all)

# All three prices in separate 3D subplots
p = plot_vol_surface_3d(surface; field=:all_price, show_all=true)

# Display it when ready
display(p)

# Or save directly
savefig(p, "vol_surface_3d.png")
```
"""
function plot_vol_surface_3d(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    title::Union{String, Vector{String}} = "Volatility Surface 3D",
    show_points::Bool = true,
    show_all::Bool = false
)
    # Handle :all and :all_price - either combine in one plot or separate subplots
    if field == :all || field == :all_price
        if show_all
            # Create three separate 3D plots
            if field == :all
                p1 = plot_vol_surface_3d(surface; field=:mid_iv, title="Mid IV", show_points=show_points)
                p2 = plot_vol_surface_3d(surface; field=:bid_iv, title="Bid IV", show_points=show_points)
                p3 = plot_vol_surface_3d(surface; field=:ask_iv, title="Ask IV", show_points=show_points)
            else  # :all_price
                p1 = plot_vol_surface_3d(surface; field=:mid_price, title="Mid Price", show_points=show_points)
                p2 = plot_vol_surface_3d(surface; field=:bid_price, title="Bid Price", show_points=show_points)
                p3 = plot_vol_surface_3d(surface; field=:ask_price, title="Ask Price", show_points=show_points)
            end
            return plot(p1, p2, p3, layout=(1,3), size=(1800, 500))
        else
            # Combine mid, bid, ask in same 3D plot with different colors
            if field == :all
                field_list = [:mid_iv, :bid_iv, :ask_iv]
            else  # :all_price
                field_list = [:mid_price, :bid_price, :ask_price]
            end
            labels = ["Mid", "Bid", "Ask"]
        end
    else
        field_list = [field]
        labels = [""]
    end
    
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv, :all]
    zlab = is_iv ? "Implied Volatility (%)" : "Price (BTC)"
    
    # Start with empty plot
    p = plot(
        xlabel="Strike", 
        ylabel="Time to Maturity (years)", 
        zlabel=zlab,
        title=title,
        camera=(45, 30),
        legend=(field == :all ? :best : false)
    )
    
    for (fld, lbl) in zip(field_list, labels)
        # Extract data for this field
        strikes = Float64[]
        ttms = Float64[]
        values = Float64[]
        
        for q in surface.quotes
            ttm = yearfrac(surface.reference_date, q.payoff.expiry)
            
            val = if fld == :mid_iv
                q.mid_iv * 100
            elseif fld == :bid_iv
                q.bid_iv * 100
            elseif fld == :ask_iv
                q.ask_iv * 100
            elseif fld == :mid_price
                q.mid_price
            elseif fld == :bid_price
                q.bid_price
            elseif fld == :ask_price
                q.ask_price
            else
                throw(ArgumentError("Unknown field: $fld"))
            end
            
            if !isnan(val)
                push!(strikes, q.payoff.strike)
                push!(ttms, ttm)
                push!(values, val)
            end
        end
        
        if isempty(strikes)
            continue
        end
        
        if show_points
            # Plot as scatter
            scatter!(p, strikes, ttms, values;
                    marker=:circle, markersize=3, alpha=0.6,
                    label=lbl)
        else
            # Plot as wireframe by grouping by expiry
            expiry_groups = Dict{Float64, Tuple{Vector{Float64}, Vector{Float64}}}()
            for (K, ttm, val) in zip(strikes, ttms, values)
                if !haskey(expiry_groups, ttm)
                    expiry_groups[ttm] = (Float64[], Float64[])
                end
                push!(expiry_groups[ttm][1], K)
                push!(expiry_groups[ttm][2], val)
            end
            
            # Sort expiries
            sorted_ttms = sort(collect(keys(expiry_groups)))
            
            # Plot surface by connecting expiry slices
            for ttm in sorted_ttms
                Ks, vals = expiry_groups[ttm]
                # Sort by strike
                perm = sortperm(Ks)
                Ks_sorted = Ks[perm]
                vals_sorted = vals[perm]
                
                plot!(p, Ks_sorted, fill(ttm, length(Ks_sorted)), vals_sorted;
                      line=:solid, linewidth=1.5, alpha=0.7, label="")
            end
            
            # Add a few connecting lines across expiries for better surface visualization
            if length(sorted_ttms) > 1
                # Sample a few strikes and connect across expiries
                all_strikes = unique(strikes)
                n_connections = min(10, length(all_strikes))
                strike_sample = sort(all_strikes)[1:Int(floor(length(all_strikes)/n_connections)):end]
                
                for K in strike_sample
                    # Find values at this strike across expiries
                    ttm_vals = Float64[]
                    val_vals = Float64[]
                    for ttm in sorted_ttms
                        Ks, vals = expiry_groups[ttm]
                        # Find closest strike
                        idx = argmin(abs.(Ks .- K))
                        if abs(Ks[idx] - K) < 0.1 * K  # Within 10% of target strike
                            push!(ttm_vals, ttm)
                            push!(val_vals, vals[idx])
                        end
                    end
                    
                    if length(ttm_vals) > 1
                        plot!(p, fill(K, length(ttm_vals)), ttm_vals, val_vals;
                              line=:solid, linewidth=1, alpha=0.5, label="")
                    end
                end
            end
        end
    end
    
    return p
end


"""
    available_expiries(surface::MarketVolSurface) -> Vector{Int}
Convenience: sorted unique expiry ticks present in `surface`.
"""
function available_expiries(surface::MarketVolSurface)
    sort(unique(q.payoff.expiry for q in surface.quotes))
end


"""
    available_expiries_dates(surface::MarketVolSurface) -> Vector{DateTime}
Convenience: expiries as `DateTime`.
"""
function available_expiries_dates(surface::MarketVolSurface)
    [Dates.epochms2datetime(e) for e in available_expiries(surface)]
end