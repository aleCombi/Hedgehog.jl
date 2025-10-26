using Plots
"""
    plot_vol_slices_by_expiry(surface::MarketVolSurface;
                              field=:mid_iv,
                              show_bid_ask=false,
                              max_expiries=5)

Plot volatility smiles for different expiries.

# Arguments
- `field`: :mid_iv, :bid_iv, :ask_iv, :mid_price, :bid_price, :ask_price, or :all (shows mid+bid+ask)
- `show_bid_ask`: If true and field is :mid_*, also shows bid/ask bands
"""
function plot_vol_slices_by_expiry(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    max_expiries::Int = 5,
    title::String = "Volatility Slices by Expiry"
)
    # Group quotes by expiry
    expiry_groups = Dict{Int64, Vector{VolQuote}}()
    for q in surface.quotes
        expiry = q.payoff.expiry
        if !haskey(expiry_groups, expiry)
            expiry_groups[expiry] = []
        end
        push!(expiry_groups[expiry], q)
    end
    
    # Sort expiries and take first max_expiries
    sorted_expiries = sort(collect(keys(expiry_groups)))
    selected_expiries = sorted_expiries[1:min(max_expiries, length(sorted_expiries))]
    
    # Determine if IV or price
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv, :all]
    ylabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"
    
    # Override show_bid_ask if field is :all
    if field == :all
        show_bid_ask = true
        base_field = :mid_iv
    else
        base_field = field
    end
    
    p = Plots.plot(xlabel="Strike", ylabel=ylabel, title=title, legend=:best)
    
    for expiry in selected_expiries
        quotes = expiry_groups[expiry]
        
        # Sort by strike
        sorted_quotes = sort(quotes, by = q -> q.payoff.strike)
        strikes = [q.payoff.strike for q in sorted_quotes]
        
        expiry_label = Dates.format(Dates.epochms2datetime(expiry), "yyyy-mm-dd")
        
        # Plot mid
        mid_field = is_iv ? (field == :all ? :mid_iv : field) : field
        mid_values = if is_iv
            [getfield(q, mid_field) * 100 for q in sorted_quotes]
        else
            [getfield(q, mid_field) for q in sorted_quotes]
        end
        
        valid_mid = .!isnan.(mid_values)
        plot!(p, strikes[valid_mid], mid_values[valid_mid], 
              label=expiry_label, marker=:circle, linewidth=2)
        
        # Add bid/ask if requested
        if show_bid_ask
            if is_iv
                bid_field = :bid_iv
                ask_field = :ask_iv
            else
                bid_field = field == :mid_price ? :bid_price : field
                ask_field = field == :mid_price ? :ask_price : field
            end
            
            bid_values = if is_iv
                [getfield(q, bid_field) * 100 for q in sorted_quotes]
            else
                [getfield(q, bid_field) for q in sorted_quotes]
            end
            
            ask_values = if is_iv
                [getfield(q, ask_field) * 100 for q in sorted_quotes]
            else
                [getfield(q, ask_field) for q in sorted_quotes]
            end
            
            valid_bid = .!isnan.(bid_values)
            valid_ask = .!isnan.(ask_values)
            
            # Plot bid/ask with dashed lines (no label, same color as mid)
            current_color = p.series_list[end][:linecolor]
            
            plot!(p, strikes[valid_bid], bid_values[valid_bid], 
                  label="", linestyle=:dash, color=current_color, alpha=0.4, linewidth=1)
            plot!(p, strikes[valid_ask], ask_values[valid_ask], 
                  label="", linestyle=:dash, color=current_color, alpha=0.4, linewidth=1)
        end
    end
    
    return p
end

"""
    plot_vol_slices_by_strike(surface::MarketVolSurface;
                              field=:mid_iv,
                              show_bid_ask=false,
                              moneyness_levels=[0.8, 0.9, 1.0, 1.1, 1.2])

Plot term structures for different moneyness levels.
"""
function plot_vol_slices_by_strike(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    moneyness_levels::Vector{Float64} = [0.8, 0.9, 1.0, 1.1, 1.2],
    title::String = "Volatility Term Structure"
)
    # Override show_bid_ask if field is :all
    if field == :all
        show_bid_ask = true
        base_field = :mid_iv
        is_iv = true
    else
        base_field = field
        is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    end
    
    # Calculate moneyness for each quote
    strikes = Float64[]
    ttms = Float64[]
    mid_values = Float64[]
    bid_values = Float64[]
    ask_values = Float64[]
    moneyness = Float64[]
    
    for q in surface.quotes
        K = q.payoff.strike
        F = q.underlying_price
        m = K / F
        ttm = yearfrac(surface.reference_date, q.payoff.expiry)
        
        mid_val = if is_iv
            q.mid_iv * 100
        else
            q.mid_price
        end
        
        if !isnan(mid_val)
            push!(strikes, K)
            push!(ttms, ttm)
            push!(mid_values, mid_val)
            push!(moneyness, m)
            
            if show_bid_ask
                bid_val = is_iv ? q.bid_iv * 100 : q.bid_price
                ask_val = is_iv ? q.ask_iv * 100 : q.ask_price
                push!(bid_values, bid_val)
                push!(ask_values, ask_val)
            end
        end
    end
    
    ylabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"
    p = plot(xlabel="Time to Maturity (years)", ylabel=ylabel, title=title, legend=:best)
    
    # For each moneyness level, find closest quotes
    tolerance = 0.05  # 5% tolerance for moneyness matching
    
    for m_target in moneyness_levels
        # Find quotes near this moneyness
        idx = findall(x -> abs(x - m_target) < tolerance, moneyness)
        
        if !isempty(idx)
            ttms_subset = ttms[idx]
            mid_subset = mid_values[idx]
            
            # Sort by TTM
            sort_idx = sortperm(ttms_subset)
            
            label = "K/F ≈ $(round(m_target, digits=2))"
            plot!(p, ttms_subset[sort_idx], mid_subset[sort_idx],
                  label=label, marker=:circle, linewidth=2)
            
            # Add bid/ask if requested
            if show_bid_ask
                bid_subset = bid_values[idx]
                ask_subset = ask_values[idx]
                
                valid_bid = .!isnan.(bid_subset)
                valid_ask = .!isnan.(ask_subset)
                
                current_color = p.series_list[end][:linecolor]
                
                if any(valid_bid)
                    plot!(p, ttms_subset[sort_idx][valid_bid], bid_subset[sort_idx][valid_bid],
                          label="", linestyle=:dash, color=current_color, alpha=0.4, linewidth=1)
                end
                
                if any(valid_ask)
                    plot!(p, ttms_subset[sort_idx][valid_ask], ask_subset[sort_idx][valid_ask],
                          label="", linestyle=:dash, color=current_color, alpha=0.4, linewidth=1)
                end
            end
        end
    end
    
    return p
end

"""
    plot_vol_surface_3d(surface::MarketVolSurface; 
                        field=:mid_iv, 
                        title="Volatility Surface",
                        show_points=true)

Create a 3D plot of the volatility surface.

# Arguments
- `field`: :mid_iv, :bid_iv, :ask_iv, :mid_price, :bid_price, :ask_price, or :all
"""
function plot_vol_surface_3d(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    title::String = "Volatility Surface",
    show_points::Bool = true
)
    if field == :all
        # Create three separate plots
        p1 = plot_vol_surface_3d(surface; field=:mid_iv, title="Mid IV")
        p2 = plot_vol_surface_3d(surface; field=:bid_iv, title="Bid IV")
        p3 = plot_vol_surface_3d(surface; field=:ask_iv, title="Ask IV")
        return plot(p1, p2, p3, layout=(1,3), size=(1800, 500))
    end
    
    # Extract data
    strikes = [q.payoff.strike for q in surface.quotes]
    ttms = [yearfrac(surface.reference_date, q.payoff.expiry) for q in surface.quotes]
    
    # Get the field values
    values = if field == :mid_iv
        [q.mid_iv * 100 for q in surface.quotes]
    elseif field == :bid_iv
        [q.bid_iv * 100 for q in surface.quotes]
    elseif field == :ask_iv
        [q.ask_iv * 100 for q in surface.quotes]
    elseif field == :mid_price
        [q.mid_price for q in surface.quotes]
    elseif field == :bid_price
        [q.bid_price for q in surface.quotes]
    elseif field == :ask_price
        [q.ask_price for q in surface.quotes]
    else
        throw(ArgumentError("Unknown field: $field"))
    end
    
    # Filter out NaNs
    valid_idx = .!isnan.(values)
    strikes_valid = strikes[valid_idx]
    ttms_valid = ttms[valid_idx]
    values_valid = values[valid_idx]
    
    # Determine axis labels
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    zlabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"
    
    # Create 3D scatter plot
    p = scatter(
        strikes_valid,
        ttms_valid,
        values_valid,
        xlabel = "Strike",
        ylabel = "Time to Maturity (years)",
        zlabel = zlabel,
        title = title,
        marker = :circle,
        markersize = 3,
        alpha = 0.6,
        camera = (45, 30),
        legend = false
    )
    
    return p
end

"""
    plot_vol_surface_overview(surface::MarketVolSurface; 
                              field=:mid_iv,
                              show_bid_ask=false,
                              max_expiries=5)

Create a comprehensive multi-panel view of the volatility surface.
"""
function plot_vol_surface_overview(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    max_expiries::Int = 5
)
    # Override for :all
    if field == :all
        show_bid_ask = true
        field = :mid_iv
    end
    
    p1 = plot_vol_surface_3d(surface; field=field, title="3D Surface")
    p2 = plot_vol_surface_heatmap(surface; field=field, title="Heatmap")
    p3 = plot_vol_slices_by_expiry(surface; field=field, show_bid_ask=show_bid_ask, 
                                     max_expiries=max_expiries, title="Smiles by Expiry")
    p4 = plot_vol_slices_by_strike(surface; field=field, show_bid_ask=show_bid_ask,
                                    title="Term Structure by Moneyness")
    
    plot(p1, p2, p3, p4, layout=(2,2), size=(1400, 1000))
end

"""
    plot_vol_smile(surface::MarketVolSurface, expiry::Union{TimeType, Int};
                   field=:mid_iv,
                   show_bid_ask=false)

Plot a single volatility smile for a specific expiry.

# Arguments
- `expiry`: Either a DateTime/Date or an expiry in ticks
"""
function plot_vol_smile(
    surface::MarketVolSurface,
    expiry::Union{TimeType, Int};
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    title::Union{String, Nothing} = nothing
)
    # Convert expiry to ticks if needed
    expiry_ticks = expiry isa TimeType ? to_ticks(expiry) : expiry
    
    # Override for :all
    if field == :all
        show_bid_ask = true
        field = :mid_iv
    end
    
    # Filter quotes for this expiry
    quotes = filter(q -> q.payoff.expiry == expiry_ticks, surface.quotes)
    
    if isempty(quotes)
        @warn "No quotes found for expiry" expiry
        return plot()
    end
    
    # Sort by strike
    sorted_quotes = sort(quotes, by = q -> q.payoff.strike)
    strikes = [q.payoff.strike for q in sorted_quotes]
    
    # Determine if IV or price
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    ylabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"
    
    # Auto title if not provided
    if isnothing(title)
        expiry_date = Dates.format(Dates.epochms2datetime(expiry_ticks), "yyyy-mm-dd")
        ttm = yearfrac(surface.reference_date, expiry_ticks)
        title = "Volatility Smile - $expiry_date (T=$(round(ttm, digits=3))y)"
    end
    
    p = plot(xlabel="Strike", ylabel=ylabel, title=title, legend=:best)
    
    # Get mid values
    mid_values = if is_iv
        [getfield(q, field) * 100 for q in sorted_quotes]
    else
        [getfield(q, field) for q in sorted_quotes]
    end
    
    valid_mid = .!isnan.(mid_values)
    plot!(p, strikes[valid_mid], mid_values[valid_mid], 
          label="Mid", marker=:circle, linewidth=2, markersize=5)
    
    # Add bid/ask if requested
    if show_bid_ask
        if is_iv
            bid_field = :bid_iv
            ask_field = :ask_iv
        else
            bid_field = field == :mid_price ? :bid_price : field
            ask_field = field == :mid_price ? :ask_price : field
        end
        
        bid_values = if is_iv
            [getfield(q, bid_field) * 100 for q in sorted_quotes]
        else
            [getfield(q, bid_field) for q in sorted_quotes]
        end
        
        ask_values = if is_iv
            [getfield(q, ask_field) * 100 for q in sorted_quotes]
        else
            [getfield(q, ask_field) for q in sorted_quotes]
        end
        
        valid_bid = .!isnan.(bid_values)
        valid_ask = .!isnan.(ask_values)
        
        plot!(p, strikes[valid_bid], bid_values[valid_bid], 
              label="Bid", linestyle=:dash, linewidth=2, alpha=0.7)
        plot!(p, strikes[valid_ask], ask_values[valid_ask], 
              label="Ask", linestyle=:dash, linewidth=2, alpha=0.7)
    end
    
    return p
end

"""
    plot_vol_term_structure(surface::MarketVolSurface, moneyness::Float64;
                            field=:mid_iv,
                            show_bid_ask=false,
                            tolerance=0.05)

Plot a single term structure for a specific moneyness level.

# Arguments
- `moneyness`: Target K/F ratio (e.g., 1.0 for ATM)
- `tolerance`: How far from target moneyness to include quotes (default: 0.05)
"""
function plot_vol_term_structure(
    surface::MarketVolSurface,
    moneyness::Float64;
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    tolerance::Real = 0.05,
    title::Union{String, Nothing} = nothing
)
    # Override for :all
    if field == :all
        show_bid_ask = true
        field = :mid_iv
    end
    
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    
    # Filter quotes near target moneyness
    filtered_quotes = []
    for q in surface.quotes
        m = q.payoff.strike / q.underlying_price
        if abs(m - moneyness) < tolerance
            push!(filtered_quotes, q)
        end
    end
    
    if isempty(filtered_quotes)
        @warn "No quotes found near moneyness" moneyness tolerance
        return plot()
    end
    
    # Sort by TTM
    sorted_quotes = sort(filtered_quotes, by = q -> yearfrac(surface.reference_date, q.payoff.expiry))
    ttms = [yearfrac(surface.reference_date, q.payoff.expiry) for q in sorted_quotes]
    
    # Auto title if not provided
    if isnothing(title)
        title = "Term Structure - K/F ≈ $(round(moneyness, digits=2))"
    end
    
    ylabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"
    p = plot(xlabel="Time to Maturity (years)", ylabel=ylabel, title=title, legend=:best)
    
    # Get mid values
    mid_values = if is_iv
        [getfield(q, field) * 100 for q in sorted_quotes]
    else
        [getfield(q, field) for q in sorted_quotes]
    end
    
    valid_mid = .!isnan.(mid_values)
    plot!(p, ttms[valid_mid], mid_values[valid_mid], 
          label="Mid", marker=:circle, linewidth=2, markersize=5)
    
    # Add bid/ask if requested
    if show_bid_ask
        if is_iv
            bid_field = :bid_iv
            ask_field = :ask_iv
        else
            bid_field = field == :mid_price ? :bid_price : field
            ask_field = field == :mid_price ? :ask_price : field
        end
        
        bid_values = if is_iv
            [getfield(q, bid_field) * 100 for q in sorted_quotes]
        else
            [getfield(q, bid_field) for q in sorted_quotes]
        end
        
        ask_values = if is_iv
            [getfield(q, ask_field) * 100 for q in sorted_quotes]
        else
            [getfield(q, ask_field) for q in sorted_quotes]
        end
        
        valid_bid = .!isnan.(bid_values)
        valid_ask = .!isnan.(ask_values)
        
        plot!(p, ttms[valid_bid], bid_values[valid_bid], 
              label="Bid", linestyle=:dash, linewidth=2, alpha=0.7)
        plot!(p, ttms[valid_ask], ask_values[valid_ask], 
              label="Ask", linestyle=:dash, linewidth=2, alpha=0.7)
    end
    
    return p
end


function plot_vol_surface_heatmap(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    title::String = "Volatility Surface Heatmap"
)
    # Extract data
    strikes = [q.payoff.strike for q in surface.quotes]
    expiries = [Dates.epochms2datetime(q.payoff.expiry) for q in surface.quotes]
    
    # Get the field values
    values = if field == :mid_iv
        [q.mid_iv * 100 for q in surface.quotes]
    elseif field == :bid_iv
        [q.bid_iv * 100 for q in surface.quotes]
    elseif field == :ask_iv
        [q.ask_iv * 100 for q in surface.quotes]
    elseif field == :mid_price
        [q.mid_price for q in surface.quotes]
    elseif field == :bid_price
        [q.bid_price for q in surface.quotes]
    elseif field == :ask_price
        [q.ask_price for q in surface.quotes]
    else
        throw(ArgumentError("Unknown field: $field"))
    end
    
    # Filter out NaNs
    valid_idx = .!isnan.(values)
    strikes_valid = strikes[valid_idx]
    expiries_valid = expiries[valid_idx]
    values_valid = values[valid_idx]
    
    # Create grid
    unique_strikes = sort(unique(strikes_valid))
    unique_expiries = sort(unique(expiries_valid))
    
    # Build matrix
    z_matrix = fill(NaN, length(unique_expiries), length(unique_strikes))
    
    for (s, e, v) in zip(strikes_valid, expiries_valid, values_valid)
        i = findfirst(==(e), unique_expiries)
        j = findfirst(==(s), unique_strikes)
        if !isnothing(i) && !isnothing(j)
            z_matrix[i, j] = v
        end
    end
    
    # Determine color label
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    clabel = is_iv ? "IV (%)" : "Price (BTC)"
    
    # Create heatmap
    p = heatmap(
        unique_strikes,
        unique_expiries,
        z_matrix,
        xlabel = "Strike",
        ylabel = "Expiry",
        title = title,
        colorbar_title = clabel,
        c = :viridis
    )
    
    return p
end

"""
    available_expiries(surface::MarketVolSurface)

Get list of available expiries in the surface.
"""
function available_expiries(surface::MarketVolSurface)
    expiries = unique([q.payoff.expiry for q in surface.quotes])
    return sort(expiries)
end

"""
    available_expiries_dates(surface::MarketVolSurface)

Get list of available expiries as DateTime objects.
"""
function available_expiries_dates(surface::MarketVolSurface)
    expiries = available_expiries(surface)
    return [Dates.epochms2datetime(e) for e in expiries]
end