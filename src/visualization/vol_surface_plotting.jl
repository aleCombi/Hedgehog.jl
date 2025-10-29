using Plots, Dates

"""
    plot_single_expiry(surface::MarketVolSurface, expiry_tick::Int; 
                       series=[:mid, :bid, :ask], metric=:price, option_type=:call)

Create one plot for a single expiry showing bid/ask/mid.

# Arguments
- `surface`: MarketVolSurface containing the quote data
- `expiry_tick`: The expiry timestamp in ticks (milliseconds since epoch)
- `series`: Which series to plot - vector containing :mid, :bid, and/or :ask
- `metric`: What to plot - :iv for implied volatility or :price for option prices
- `option_type`: :call, :put, or :both to plot calls, puts, or both separately

# Returns
- A single plot object for that expiry

# Examples
```julia
expiries = sort(unique(q.payoff.expiry for q in surface.quotes))
# Plot calls only
p = plot_single_expiry(surface, expiries[1]; series=[:mid, :bid, :ask], metric=:price, option_type=:call)
display(p)

# Plot both calls and puts
p = plot_single_expiry(surface, expiries[1]; series=[:mid], metric=:price, option_type=:both)
display(p)
```
"""
function plot_single_expiry(
    surface::MarketVolSurface, 
    expiry_tick::Int;
    series::Vector{Symbol} = [:mid, :bid, :ask],
    metric::Symbol = :price,
    option_type::Symbol = :call
)
    # Validate inputs
    for s in series
        s in [:mid, :bid, :ask] || throw(ArgumentError("series must contain only :mid, :bid, or :ask. Got: $s"))
    end
    metric in [:iv, :price] || throw(ArgumentError("metric must be :iv or :price. Got: $metric"))
    option_type in [:call, :put, :both] || throw(ArgumentError("option_type must be :call, :put, or :both. Got: $option_type"))
    
    # Get quotes for this specific expiry only
    quotes_for_expiry = filter(q -> q.payoff.expiry == expiry_tick, surface.quotes)
    
    if isempty(quotes_for_expiry)
        error("No quotes found for expiry tick: $expiry_tick")
    end
    
    # Setup plot labels
    ylabel = metric == :iv ? "Implied Volatility (%)" : "Price (BTC)"
    expiry_date = Dates.format(Dates.epochms2datetime(expiry_tick), "yyyy-mm-dd HH:MM")
    title_str = "$(expiry_date) - $(metric == :iv ? "Implied Volatility" : "Prices")"
    
    # Create empty plot
    p = plot(xlabel="Strike", ylabel=ylabel, title=title_str, legend=:best)
    
    # Determine which option types to plot
    types_to_plot = if option_type == :both
        [:call, :put]
    else
        [option_type]
    end
    
    # Plot each option type
    for opt_type in types_to_plot
        # Filter quotes by option type
        is_call = opt_type == :call
        filtered_quotes = filter(q -> isa(q.payoff.call_put, Call) == is_call, quotes_for_expiry)
        
        if isempty(filtered_quotes)
            @warn "No $(opt_type)s found for this expiry"
            continue
        end
        
        # Sort by strike
        sort!(filtered_quotes, by = q -> q.payoff.strike)
        
        # Extract strikes
        strikes = [q.payoff.strike for q in filtered_quotes]
        
        # Plot each series
        for s in series
            # Map series type to field name
            field = if s == :mid
                metric == :iv ? :mid_iv : :mid_price
            elseif s == :bid
                metric == :iv ? :bid_iv : :bid_price
            else  # :ask
                metric == :iv ? :ask_iv : :ask_price
            end
            
            # Extract values
            values = [getfield(q, field) for q in filtered_quotes]
            
            # Convert IV to percentage
            if metric == :iv
                values = values .* 100
            end
            
            # Filter NaN
            valid_idx = .!isnan.(values)
            
            # Plot if we have valid data
            if any(valid_idx)
                # Create label
                label = if option_type == :both
                    "$(titlecase(string(opt_type))) $(titlecase(string(s)))"
                elseif length(series) > 1
                    titlecase(string(s))
                else
                    ""  # No label if single series and single option type
                end
                
                # Line style
                linestyle = s == :mid ? :solid : (s == :bid ? :dash : :dot)
                
                # Marker shape differs by option type when plotting both
                marker = (option_type == :both && opt_type == :put) ? :square : :circle
                
                plot!(p, strikes[valid_idx], values[valid_idx];
                      label=label, marker=marker, markersize=4, linewidth=2, linestyle=linestyle)
            end
        end
    end
    
    return p
end

"""
    plot_all_expiries_separately(surface::MarketVolSurface; 
                                  series=[:mid, :bid, :ask], 
                                  metric=:price, 
                                  max_expiries=nothing,
                                  option_type=:call)

Create one separate plot for each expiry in the surface.

# Arguments
- `surface`: MarketVolSurface containing the quote data
- `series`: Which series to plot - vector containing :mid, :bid, and/or :ask
- `metric`: What to plot - :iv for implied volatility or :price for option prices
- `max_expiries`: Maximum number of expiries to plot (nothing = all)
- `option_type`: :call, :put, or :both to plot calls, puts, or both separately

# Returns
- Vector of plot objects, one per expiry

# Examples
```julia
# Plot calls only
plots = plot_all_expiries_separately(surface; series=[:mid, :bid, :ask], metric=:price, max_expiries=10, option_type=:call)
for p in plots
    display(p)
end

# Plot both calls and puts on same plots
plots = plot_all_expiries_separately(surface; series=[:mid], metric=:price, option_type=:both)
```
"""
function plot_all_expiries_separately(
    surface::MarketVolSurface;
    series::Vector{Symbol} = [:mid, :bid, :ask],
    metric::Symbol = :price,
    max_expiries::Union{Nothing, Int} = nothing,
    option_type::Symbol = :call
)
    # Get all unique expiries, sorted
    expiries = sort(unique(q.payoff.expiry for q in surface.quotes))
    
    # Limit if requested
    if !isnothing(max_expiries)
        expiries = expiries[1:min(max_expiries, length(expiries))]
    end
    
    # Create one plot per expiry
    plots = []
    for expiry in expiries
        p = plot_single_expiry(surface, expiry; series=series, metric=metric, option_type=option_type)
        push!(plots, p)
    end
    
    return plots
end

"""
    plot_expiry_by_index(surface::MarketVolSurface, idx::Int; 
                         series=[:mid, :bid, :ask], metric=:price, option_type=:call)

Plot a specific expiry by its index (1-indexed, sorted by time).

# Arguments
- `surface`: MarketVolSurface containing the quote data
- `idx`: Index of the expiry to plot (1 = earliest, 2 = second earliest, etc.)
- `series`: Which series to plot - vector containing :mid, :bid, and/or :ask
- `metric`: What to plot - :iv for implied volatility or :price for option prices
- `option_type`: :call, :put, or :both to plot calls, puts, or both separately

# Returns
- A single plot object for that expiry

# Examples
```julia
# Plot the 3rd expiry (calls only)
p = plot_expiry_by_index(surface, 3; series=[:mid, :bid, :ask], metric=:price, option_type=:call)
display(p)

# Plot the 3rd expiry (both calls and puts)
p = plot_expiry_by_index(surface, 3; series=[:mid], metric=:price, option_type=:both)
display(p)
```
"""
function plot_expiry_by_index(
    surface::MarketVolSurface, 
    idx::Int; 
    series::Vector{Symbol} = [:mid, :bid, :ask],
    metric::Symbol = :price,
    option_type::Symbol = :call
)
    expiries = sort(unique(q.payoff.expiry for q in surface.quotes))
    
    if idx < 1 || idx > length(expiries)
        error("Index $idx out of range. Valid range: 1 to $(length(expiries))")
    end
    
    return plot_single_expiry(surface, expiries[idx]; series=series, metric=metric, option_type=option_type)
end

"""
    plot_all_expiries_grid(surface::MarketVolSurface; 
                           series=[:mid, :bid, :ask], 
                           metric=:price,
                           max_expiries=nothing,
                           option_type=:call,
                           layout=nothing,
                           size=(1200, 800))

Create a grid of plots showing all expiries in a single figure.

# Arguments
- `surface`: MarketVolSurface containing the quote data
- `series`: Which series to plot - vector containing :mid, :bid, and/or :ask
- `metric`: What to plot - :iv for implied volatility or :price for option prices
- `max_expiries`: Maximum number of expiries to plot (nothing = all)
- `option_type`: :call, :put, or :both to plot calls, puts, or both separately
- `layout`: Tuple (rows, cols) for grid layout. If nothing, automatically determined
- `size`: Figure size as tuple (width, height)

# Returns
- A single plot object containing all expiries in a grid

# Examples
```julia
# Plot all expiries in an auto-determined grid (calls only)
p = plot_all_expiries_grid(surface; series=[:mid, :bid, :ask], metric=:price, option_type=:call)
display(p)

# Plot first 6 expiries in a 2x3 grid (both calls and puts)
p = plot_all_expiries_grid(surface; series=[:mid], metric=:price, max_expiries=6, 
                           option_type=:both, layout=(2, 3))
display(p)

# Plot with custom figure size
p = plot_all_expiries_grid(surface; series=[:mid], metric=:iv, 
                           option_type=:call, size=(1600, 1000))
display(p)
```
"""
function plot_all_expiries_grid(
    surface::MarketVolSurface;
    series::Vector{Symbol} = [:mid, :bid, :ask],
    metric::Symbol = :price,
    max_expiries::Union{Nothing, Int} = nothing,
    option_type::Symbol = :call,
    layout::Union{Nothing, Tuple{Int, Int}} = nothing,
    size::Tuple{Int, Int} = (1200, 800)
)
    # Get all the individual plots
    plots = plot_all_expiries_separately(surface; 
                                        series=series, 
                                        metric=metric, 
                                        max_expiries=max_expiries,
                                        option_type=option_type)
    
    n_plots = length(plots)
    
    if n_plots == 0
        error("No plots to display")
    end
    
    # Determine layout if not specified
    if isnothing(layout)
        # Aim for roughly square grid, slightly favoring more columns
        ncols = ceil(Int, sqrt(n_plots * 1.2))
        nrows = ceil(Int, n_plots / ncols)
        layout = (nrows, ncols)
    end
    
    # Combine all plots into a grid
    combined_plot = plot(plots..., layout=layout, size=size, 
                         plot_title="$(metric == :iv ? "Implied Volatility" : "Price") Surface - All Expiries")
    
    return combined_plot
end