# Underlying info types
abstract type UnderlyingInfo end

struct SpotBasedInfo{TV <: Real, TR <: AbstractRateCurve} <: UnderlyingInfo
    spot::TV
    rate_curve::TR
end

struct FuturesBasedInfo{TF <: AbstractForwardCurve} <: UnderlyingInfo
    futures_curve::TF
end

# Main struct
struct MarketVolSurface{TQuote <: VolQuote, TTime <: Real, TUnderlying <: UnderlyingInfo}
    quotes::Vector{TQuote}
    reference_date::TTime  # In ticks
    underlying_info::TUnderlying
end

"""
    MarketVolSurface(quotes::Vector{VolQuote}; kwargs...)

Construct a MarketVolSurface from a vector of quotes, automatically building underlying info.

# Arguments
- `quotes`: Vector of VolQuote objects

# Keyword Arguments
- `reference_date::Union{Nothing, TimeType, Real} = nothing`: Reference date for the surface (defaults to latest quote timestamp)
- `spot::Union{Nothing, Real} = nothing`: Spot price (required for SpotUnderlying quotes)
- `rate_curve::Union{Nothing, AbstractRateCurve} = nothing`: Rate curve (required for SpotUnderlying quotes)
- `futures_curve::Union{Nothing, AbstractForwardCurve} = nothing`: Optional pre-built futures curve (otherwise extracted from quotes)
- `timestamp_tolerance::Union{Nothing, Period} = nothing`: Maximum allowed time difference between quotes
- `underlying_price_tolerance::Real = 1e-4`: Relative tolerance for underlying price consistency

# Behavior
1. Validates all quotes have consistent underlying_type
2. Determines common reference_date (defaults to latest timestamp)
3. For FutureUnderlying: builds futures curve from quotes (or validates provided one)
4. For SpotUnderlying: bundles spot + rate_curve into SpotBasedInfo
5. Validates underlying price coherence across quotes
"""
function MarketVolSurface(
    quotes::Vector{<:VolQuote};
    reference_date::Union{Nothing, TimeType, Real} = nothing,
    spot::Union{Nothing, Real} = nothing,
    rate_curve::Union{Nothing, AbstractRateCurve} = nothing,
    futures_curve::Union{Nothing, AbstractForwardCurve} = nothing,
    timestamp_tolerance::Union{Nothing, Period} = nothing,
    underlying_price_tolerance::Real = 1e-4,
)
    if isempty(quotes)
        throw(ArgumentError("Cannot create MarketVolSurface from empty quote vector"))
    end
    
    # Step 1: Check all quotes have same underlying_type
    underlying_types = unique(q.underlying_type for q in quotes)
    if length(underlying_types) > 1
        throw(ArgumentError("Mixed underlying types in quotes: $underlying_types. All quotes must have the same underlying type."))
    end
    underlying_type = first(underlying_types)
    
    # Only support Spot and Futures
    if underlying_type == ForwardUnderlying
        @warn "ForwardUnderlying type detected - treating as FutureUnderlying (forwards ≈ futures for pricing)"
        underlying_type = FutureUnderlying
    end
    
    # Step 1b: Check timestamp coherence
    timestamps = [q.timestamp for q in quotes]
    earliest = minimum(timestamps)
    latest = maximum(timestamps)
    
    if !isnothing(timestamp_tolerance)
        time_span = latest - earliest  # In ticks (milliseconds)
        allowed_span = Dates.value(timestamp_tolerance)  # Convert Period to milliseconds
        if time_span > allowed_span
            @warn "Quote timestamps span $(time_span/1000/60) minutes, exceeds tolerance" earliest=Dates.epochms2datetime(earliest) latest=Dates.epochms2datetime(latest)
        end
    end
    
    # Step 2: Determine reference date
    ref_date_ticks = if isnothing(reference_date)
        latest  # Use most recent quote timestamp
    else
        provided_ref_ticks = to_ticks(reference_date)
        
        # Check if provided reference date is close to quote timestamps
        if !isnothing(timestamp_tolerance)
            max_distance = max(abs(provided_ref_ticks - earliest), abs(provided_ref_ticks - latest))
            allowed_span = Dates.value(timestamp_tolerance)
            
            if max_distance > allowed_span
                @warn "Provided reference_date is far from quote timestamps" reference_date=Dates.epochms2datetime(provided_ref_ticks) earliest_quote=Dates.epochms2datetime(earliest) latest_quote=Dates.epochms2datetime(latest) max_distance_minutes=max_distance/1000/60
            end
        end
        
        provided_ref_ticks
    end
    
    # Step 3: Build underlying_info based on underlying_type
    if underlying_type == FutureUnderlying
        # Build or validate futures curve
        if isnothing(futures_curve)
            # Extract curve from quotes and build FuturesCurve
            futures_curve = build_futures_curve_from_quotes(quotes, ref_date_ticks; tolerance=underlying_price_tolerance)
        else
            # Validate provided curve against quotes
            validate_futures_curve_against_quotes(futures_curve, quotes, underlying_price_tolerance)
        end
        
        underlying_info = FuturesBasedInfo(futures_curve)
        
    elseif underlying_type == SpotUnderlying
        # Bundle spot + rate_curve
        if isnothing(spot) || isnothing(rate_curve)
            throw(ArgumentError("For SpotUnderlying quotes, must provide both `spot` and `rate_curve` keyword arguments"))
        end
        
        # Validate spot against quote underlying_prices
        validate_spot_against_quotes(spot, quotes, underlying_price_tolerance)
        
        underlying_info = SpotBasedInfo(spot, rate_curve)
        
    else
        throw(ArgumentError("Unknown underlying type: $underlying_type. Must be SpotUnderlying or FutureUnderlying."))
    end
    
    # Build the surface
    TQuote = eltype(quotes)
    TTime = typeof(ref_date_ticks)
    TUnderlying = typeof(underlying_info)
    
    return MarketVolSurface{TQuote, TTime, TUnderlying}(
        quotes,
        ref_date_ticks,
        underlying_info
    )
end

"""
    get_forward(info::UnderlyingInfo, expiry::Real)

Get the forward price at a given expiry from the underlying info.

# Arguments
- `info`: UnderlyingInfo (SpotBasedInfo or FuturesBasedInfo)
- `expiry`: Expiry time in ticks

# Returns
- Forward price at the given expiry
"""
function get_forward(info::SpotBasedInfo, expiry::Real)
    # For spot-based: compute forward = spot * exp(r * T)
    ref_date = info.rate_curve.reference_date
    T = yearfrac(ref_date, expiry)
    r = zero_rate_yf(info.rate_curve, T)
    return info.spot * exp(r * T)
end

function get_forward(info::FuturesBasedInfo, expiry::Real)
    # Delegate to the FuturesCurve get_forward method
    return get_forward(info.futures_curve, expiry)
end

"""
    validate_futures_curve_against_quotes(curve, quotes, tolerance)

Check that provided futures curve is consistent with quote underlying prices.
"""
function validate_futures_curve_against_quotes(
    curve::AbstractForwardCurve,
    quotes::Vector{<:VolQuote},
    tolerance::Real
)
    # Group quotes by expiry
    expiry_groups = Dict{Real, Vector{Float64}}()
    
    for q in quotes
        expiry = q.payoff.expiry
        if !haskey(expiry_groups, expiry)
            expiry_groups[expiry] = []
        end
        push!(expiry_groups[expiry], q.underlying_price)
    end
    
    # Check each expiry against curve
    for (expiry, prices) in expiry_groups
        mean_price = mean(prices)
        
        # Get curve value at this expiry
        curve_value = get_forward(curve, expiry)
        
        relative_error = abs(curve_value - mean_price) / mean_price
        if relative_error > tolerance
            @warn "Futures curve inconsistent with quotes" expiry=Dates.epochms2datetime(expiry) curve_value quote_mean=mean_price relative_error
        end
    end
end

"""
    validate_spot_against_quotes(spot, quotes, tolerance)

Check that provided spot price is consistent with quote underlying prices.
"""
function validate_spot_against_quotes(
    spot::Real,
    quotes::Vector{<:VolQuote},
    tolerance::Real
)
    underlying_prices = [q.underlying_price for q in quotes]
    mean_price = mean(underlying_prices)
    min_price = minimum(underlying_prices)
    max_price = maximum(underlying_prices)
    
    # Check against mean
    relative_error = abs(spot - mean_price) / mean_price
    if relative_error > tolerance
        @warn "Provided spot differs from quote underlying prices" spot quote_mean=mean_price quote_min=min_price quote_max=max_price relative_error
    end
    
    # Also check spread within quotes
    price_spread = (max_price - min_price) / mean_price
    if price_spread > tolerance
        @warn "Large spread in quote underlying prices" mean=mean_price min=min_price max=max_price relative_spread=price_spread
    end
end