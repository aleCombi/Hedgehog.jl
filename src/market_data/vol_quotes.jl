@enum UnderlyingType SpotUnderlying FutureUnderlying ForwardUnderlying

struct VolQuote{TPayoff <: AbstractPayoff, TV <: Real}
    payoff::TPayoff
    underlying_price::TV
    underlying_type::UnderlyingType  # What underlying_price represents: SpotUnderlying, FutureUnderlying, or ForwardUnderlying
    
    # Volatility quotes
    mid_iv::TV
    bid_iv::TV
    ask_iv::TV
    
    # Price quotes
    mid_price::TV
    bid_price::TV
    ask_price::TV
    last_price::TV
    
    # Market microstructure
    open_interest::TV
    volume::TV
    
    # Metadata
    timestamp::TV  # Stored as ticks (milliseconds since epoch)
    source::Symbol
end

function VolQuote(
    strike::Real,
    expiry::Union{TimeType, Real},
    option_type::AbstractCallPut,
    underlying_price::Real,
    mid_iv::Real,
    timestamp::Union{TimeType, Real};
    underlying_type::UnderlyingType = SpotUnderlying,
    bid_iv::Real = NaN,
    ask_iv::Real = NaN,
    mid_price::Real = NaN,
    bid_price::Real = NaN,
    ask_price::Real = NaN,
    last_price::Real = NaN,
    open_interest::Real = NaN,
    volume::Real = NaN,
    source::Symbol = :unknown,
    exercise_style::AbstractExerciseStyle = European(),
    underlying::Underlying = Spot(),
    rate_curve::Union{Nothing, AbstractRateCurve} = nothing,
    reference_date::Union{Nothing, TimeType, Real} = nothing,
    price_tolerance::Real = 1e-2,
)
    if exercise_style isa American
        throw(ArgumentError("American option pricing not yet implemented. VolQuote currently only supports European options. American options require Barone-Adesi-Whaley approximation which is not yet available."))
    end
    # Convert TimeTypes to internal tick representation
    expiry_ticks = to_ticks(expiry)
    timestamp_ticks = to_ticks(timestamp)
    
    # Construct the option payoff
    payoff = VanillaOption(strike, expiry_ticks, exercise_style, option_type, underlying)
    
    # Determine if we can compute prices from IVs
    can_price = !isnothing(rate_curve) || underlying_type != SpotUnderlying
    
    if can_price
        # Determine reference date for pricing calculations
        ref_date = isnothing(reference_date) ? timestamp : reference_date        
        
        # Compute forward price for pricing
        forward = if underlying_type == SpotUnderlying
            # Need to compute forward from spot using rate curve
            T = yearfrac(ref_date, expiry_ticks)
            underlying_price * exp(zero_rate_yf(rate_curve, T) * T)
        else
            # underlying_price is already forward/futures price
            underlying_price
        end
        
        # Set up Black-Scholes pricer with zero rate (forward pricing)
        zero_rate_curve = FlatRateCurve(0.0; reference_date=ref_date)
        
        compute_price = function(iv)
            market_inputs = BlackScholesInputs(ref_date, zero_rate_curve, forward, iv)
            prob = PricingProblem(payoff, market_inputs)
            return solve(prob, BlackScholesAnalytic()).price / underlying_price
        end
        
        # Compute and validate mid price (always have mid_iv)
        computed_mid = compute_price(mid_iv)
        final_mid = validate_and_select_price(
            mid_price, computed_mid, price_tolerance,
            "Mid", strike, expiry_ticks, option_type
        )
        
        # Compute and validate bid price (only if bid_iv provided)
        final_bid = if isnan(bid_iv)
            bid_price  # Just use provided (or NaN)
        else
            computed_bid = compute_price(bid_iv)
            validate_and_select_price(
                bid_price, computed_bid, price_tolerance,
                "Bid", strike, expiry_ticks, option_type
            )
        end
        
        # Compute and validate ask price (only if ask_iv provided)
        final_ask = if isnan(ask_iv)
            ask_price  # Just use provided (or NaN)
        else
            computed_ask = compute_price(ask_iv)
            validate_and_select_price(
                ask_price, computed_ask, price_tolerance,
                "Ask", strike, expiry_ticks, option_type
            )
        end
    else
        # Cannot compute prices - use provided values or NaN
        final_mid = mid_price
        final_bid = bid_price
        final_ask = ask_price
    end
    
    # Promote all numeric types to common type
    TV = promote_type(
        typeof(underlying_price), typeof(mid_iv), typeof(bid_iv), typeof(ask_iv),
        typeof(final_mid), typeof(final_bid), typeof(final_ask), typeof(last_price),
        typeof(open_interest), typeof(volume), typeof(timestamp_ticks)
    )
    
    return VolQuote{typeof(payoff), TV}(
        payoff,
        TV(underlying_price),
        underlying_type,
        TV(mid_iv),
        TV(bid_iv),
        TV(ask_iv),
        TV(final_mid),
        TV(final_bid),
        TV(final_ask),
        TV(last_price),
        TV(open_interest),
        TV(volume),
        TV(timestamp_ticks),
        source
    )
end

"""
    validate_and_select_price(provided, computed, tolerance, label, strike, expiry, option_type)

Helper function to validate provided price against computed price or use computed if not provided.
Warns if discrepancy exceeds tolerance.
"""
function validate_and_select_price(
    provided::Real,
    computed::Real,
    tolerance::Real,
    label::String,
    strike::Real,
    expiry::Real,
    option_type::AbstractCallPut
)
    if isnan(provided)
        return computed
    else
        error = abs(computed - provided) / max(abs(provided), 1e-10)
        if error > tolerance
            @warn "$label price-IV inconsistency detected" strike expiry option_type provided computed relative_error=error
        end
        return provided
    end
end