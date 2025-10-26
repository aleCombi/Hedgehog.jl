using Plots

"""
    plot_vol_2d_by_expiry(surface::MarketVolSurface;
                          field=:mid_iv,
                          show_bid_ask=false,
                          max_expiries=typemax(Int),
                          title="Volatility Slices by Expiry")

Plot volatility smiles for multiple expiries on the same 2D graph.

Arguments
- `field`: one of :mid_iv, :bid_iv, :ask_iv, :mid_price, :bid_price, :ask_price
- `show_bid_ask`: if true and `field` is a :mid_* value, also draws bid/ask as dashed lines
- `max_expiries`: limit the number of expiries plotted (useful on very dense surfaces)

Returns
- `p::Plots.Plot`
"""
function plot_vol_2d_by_expiry(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    show_bid_ask::Bool = false,
    max_expiries::Int = typemax(Int),
    title::String = "Volatility Slices by Expiry"
)
    # determine IV vs price
    is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    ylabel = is_iv ? "Implied Volatility (%)" : "Price (BTC)"

    # if mid_* and show_bid_ask, map corresponding bid/ask fields
    bid_field = is_iv ? :bid_iv  : (field == :mid_price ? :bid_price : field)
    ask_field = is_iv ? :ask_iv  : (field == :mid_price ? :ask_price : field)

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

    p = plot(xlabel="Strike", ylabel=ylabel, title=title, legend=:best)

    for e in expiries
        qs = sort(groups[e], by = q -> q.payoff.strike)
        strikes = [q.payoff.strike for q in qs]

        # main series
        vals = if is_iv
            [getfield(q, field) * 100 for q in qs]
        else
            [getfield(q, field) for q in qs]
        end
        ok = .!isnan.(vals)

        label = Dates.format(Dates.epochms2datetime(e), "yyyy-mm-dd")
        plot!(p, strikes[ok], vals[ok]; label, marker=:circle, linewidth=2)

        # optional bid/ask bands (same color, dashed, unlabeled)
        if show_bid_ask && (field == :mid_iv || field == :mid_price)
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
                        show_points=true)

3D scatter of the surface over (Strike, Time to Maturity). Suitable for irregular grids.

Arguments
- `field`: one of :mid_iv, :bid_iv, :ask_iv, :mid_price, :bid_price, :ask_price
- `show_points`: kept for API symmetry; 3D is plotted as scatter.

Returns
- `p::Plots.Plot`
"""
function plot_vol_surface_3d(
    surface::MarketVolSurface;
    field::Symbol = :mid_iv,
    title::String = "Volatility Surface 3D",
    show_points::Bool = true
)
    # axes
    strikes = [q.payoff.strike for q in surface.quotes]
    ttms    = [yearfrac(surface.reference_date, q.payoff.expiry) for q in surface.quotes]

    # z values
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

    valid = .!isnan.(values)
    strikes = strikes[valid]
    ttms    = ttms[valid]
    values  = values[valid]

    is_iv = field in [:mid_iv, :bid_iv, :ask_iv]
    zlab  = is_iv ? "Implied Volatility (%)" : "Price (BTC)"

    p = scatter(
        strikes, ttms, values;
        xlabel="Strike", ylabel="Time to Maturity (years)", zlabel=zlab,
        title, marker=:circle, markersize=3, alpha=0.6,
        camera=(45, 30), legend=false
    )
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
