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
        
        # --- Process MID values ---
        # Compute mid price from mid_iv (always have mid_iv)
        computed_mid_price = iv_to_price(payoff, forward, mid_iv, ref_date)
        final_mid_price = validate_and_select_price(
            mid_price, computed_mid_price, price_tolerance,
            "Mid", strike, expiry_ticks, option_type
        )
        final_mid_iv = mid_iv  # Mid IV is always provided
        
        # --- Process BID values ---
        if !isnan(bid_iv) && !isnan(bid_price)
            # Both bid_iv and bid_price provided - validate consistency
            computed_bid_price = iv_to_price(payoff, forward, bid_iv, ref_date)
            final_bid_price = validate_and_select_price(
                bid_price, computed_bid_price, price_tolerance,
                "Bid", strike, expiry_ticks, option_type
            )
            final_bid_iv = bid_iv
        elseif !isnan(bid_iv)
            # Only bid_iv provided - compute bid_price
            final_bid_price = iv_to_price(payoff, forward, bid_iv, ref_date)
            final_bid_iv = bid_iv
        elseif !isnan(bid_price)
            # Only bid_price provided - compute bid_iv
            final_bid_iv = price_to_iv(payoff, forward, bid_price, ref_date; iv_guess=mid_iv)
            final_bid_price = bid_price
        else
            # Neither provided
            final_bid_iv = NaN
            final_bid_price = NaN
        end
        
        # --- Process ASK values ---
        if !isnan(ask_iv) && !isnan(ask_price)
            # Both ask_iv and ask_price provided - validate consistency
            computed_ask_price = iv_to_price(payoff, forward, ask_iv, ref_date)
            final_ask_price = validate_and_select_price(
                ask_price, computed_ask_price, price_tolerance,
                "Ask", strike, expiry_ticks, option_type
            )
            final_ask_iv = ask_iv
        elseif !isnan(ask_iv)
            # Only ask_iv provided - compute ask_price
            final_ask_price = iv_to_price(payoff, forward, ask_iv, ref_date)
            final_ask_iv = ask_iv
        elseif !isnan(ask_price)
            # Only ask_price provided - compute ask_iv
            final_ask_iv = price_to_iv(payoff, forward, ask_price, ref_date; iv_guess=mid_iv)
            final_ask_price = ask_price
        else
            # Neither provided
            final_ask_iv = NaN
            final_ask_price = NaN
        end
    else
        # Cannot compute prices - use provided values or NaN
        final_mid_price = mid_price
        final_mid_iv = mid_iv
        final_bid_price = bid_price
        final_bid_iv = bid_iv
        final_ask_price = ask_price
        final_ask_iv = ask_iv
    end
    
    # Promote all numeric types to common type
    TV = promote_type(
        typeof(underlying_price), typeof(final_mid_iv), typeof(final_bid_iv), typeof(final_ask_iv),
        typeof(final_mid_price), typeof(final_bid_price), typeof(final_ask_price), typeof(last_price),
        typeof(open_interest), typeof(volume), typeof(timestamp_ticks)
    )
    
    return VolQuote{typeof(payoff), TV}(
        payoff,
        TV(underlying_price),
        underlying_type,
        TV(final_mid_iv),
        TV(final_bid_iv),
        TV(final_ask_iv),
        TV(final_mid_price),
        TV(final_bid_price),
        TV(final_ask_price),
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

"""
    iv_to_price(payoff::AbstractPayoff, 
                underlying_price::Real,
                iv::Real,
                reference_date::Union{TimeType, Real})

Convert implied volatility to option price.

# Arguments
- `payoff`: The option payoff specification
- `underlying_price`: The forward/futures price of the underlying
- `iv`: The implied volatility to convert
- `reference_date`: Reference date for pricing

# Returns
- Option price in units of the underlying (normalized price)

# Notes
Assumes `underlying_price` is a forward price. Uses zero rate curve for forward pricing.
"""
function iv_to_price(
    payoff::AbstractPayoff,
    underlying_price::Real,
    iv::Real,
    reference_date::Union{TimeType, Real}
)
    # Set up Black-Scholes pricer with zero rate (forward pricing)
    zero_rate_curve = FlatRateCurve(0.0; reference_date=reference_date)
    
    # Price the option
    market_inputs = BlackScholesInputs(reference_date, zero_rate_curve, underlying_price, iv)
    prob = PricingProblem(payoff, market_inputs)
    
    # Return normalized price (in units of underlying)
    return solve(prob, BlackScholesAnalytic()).price / underlying_price
end


"""
    iv_to_price(vol_quote::VolQuote, iv::Real; 
                rate_curve::Union{Nothing, AbstractRateCurve} = nothing,
                reference_date::Union{Nothing, TimeType, Real} = nothing)

Convert implied volatility to option price for a given VolQuote.

# Arguments
- `vol_quote`: The VolQuote containing the option specification
- `iv`: The implied volatility to convert
- `rate_curve`: Optional rate curve (required if underlying_type is SpotUnderlying)
- `reference_date`: Optional reference date for pricing (defaults to vol_quote.timestamp)

# Returns
- Option price in units of the underlying (normalized price)
"""
function iv_to_price(
    vol_quote::VolQuote,
    iv::Real;
    rate_curve::Union{Nothing, AbstractRateCurve} = nothing,
    reference_date::Union{Nothing, TimeType, Real} = nothing
)
    # Check if we can price
    can_price = !isnothing(rate_curve) || vol_quote.underlying_type != SpotUnderlying
    
    if !can_price
        throw(ArgumentError("Cannot compute price from IV: underlying_type is SpotUnderlying but no rate_curve provided"))
    end
    
    # Determine reference date
    ref_date = isnothing(reference_date) ? vol_quote.timestamp : reference_date
    
    # Compute forward price
    forward = if vol_quote.underlying_type == SpotUnderlying
        # Need to compute forward from spot using rate curve
        T = yearfrac(ref_date, vol_quote.payoff.expiry)
        vol_quote.underlying_price * exp(zero_rate_yf(rate_curve, T) * T)
    else
        # underlying_price is already forward/futures price
        vol_quote.underlying_price
    end
    
    # Call the core function
    return iv_to_price(vol_quote.payoff, forward, iv, ref_date)
end


"""
    price_to_iv(payoff::AbstractPayoff,
                underlying_price::Real,
                price::Real,
                reference_date::Union{TimeType, Real};
                iv_guess::Real = 0.5)

Convert option price to implied volatility using Hedgehog's calibration framework.

# Arguments
- `payoff`: The option payoff specification
- `underlying_price`: The forward/futures price of the underlying
- `price`: The option price (normalized, in units of underlying)
- `reference_date`: Reference date for pricing
- `iv_guess`: Initial guess for IV (default: 0.5 = 50%)

# Returns
- Implied volatility

# Notes
Assumes `underlying_price` is a forward price. Uses zero rate curve for forward pricing.
Uses Hedgehog's CalibrationProblem with RootFinderAlgo for robust root finding.
"""
function price_to_iv(
    payoff::AbstractPayoff,
    underlying_price::Real,
    price::Real,
    reference_date::Union{TimeType, Real};
    iv_guess::Real = 0.5
)
    # Set up zero rate curve for forward pricing
    zero_rate_curve = FlatRateCurve(0.0; reference_date=reference_date)
    
    # Build market inputs with initial guess
    market_inputs = BlackScholesInputs(reference_date, zero_rate_curve, underlying_price, iv_guess)
    
    # Denormalize price back to absolute units for calibration
    target_price = price * underlying_price
    
    # Create calibration problem
    calib = CalibrationProblem(
        BasketPricingProblem([payoff], market_inputs),
        BlackScholesAnalytic(),
        [VolLens(1, 1)],  # Calibrate vol parameter
        [target_price],
        [iv_guess]
    )
    
    # Solve for implied vol using root finding
    sol = Hedgehog.solve(calib, RootFinderAlgo())
    
    # Extract implied vol
    return sol.u[1]
end


"""
    price_to_iv(vol_quote::VolQuote, price::Real;
                rate_curve::Union{Nothing, AbstractRateCurve} = nothing,
                reference_date::Union{Nothing, TimeType, Real} = nothing,
                iv_guess::Real = 0.5)

Convert option price to implied volatility for a given VolQuote using Hedgehog's calibration framework.

# Arguments
- `vol_quote`: The VolQuote containing the option specification
- `price`: The option price (normalized, in units of underlying)
- `rate_curve`: Optional rate curve (required if underlying_type is SpotUnderlying)
- `reference_date`: Optional reference date for pricing (defaults to vol_quote.timestamp)
- `iv_guess`: Initial guess for IV (default: 0.5 = 50%)

# Returns
- Implied volatility

# Notes
Uses Hedgehog's CalibrationProblem with RootFinderAlgo for robust root finding.
"""
function price_to_iv(
    vol_quote::VolQuote,
    price::Real;
    rate_curve::Union{Nothing, AbstractRateCurve} = nothing,
    reference_date::Union{Nothing, TimeType, Real} = nothing,
    iv_guess::Real = 0.5
)
    # Check if we can price
    can_price = !isnothing(rate_curve) || vol_quote.underlying_type != SpotUnderlying
    
    if !can_price
        throw(ArgumentError("Cannot compute IV from price: underlying_type is SpotUnderlying but no rate_curve provided"))
    end
    
    # Determine reference date
    ref_date = isnothing(reference_date) ? vol_quote.timestamp : reference_date
    
    # Compute forward price
    forward = if vol_quote.underlying_type == SpotUnderlying
        T = yearfrac(ref_date, vol_quote.payoff.expiry)
        vol_quote.underlying_price * exp(zero_rate_yf(rate_curve, T) * T)
    else
        vol_quote.underlying_price
    end
    
    # Call the core function
    return price_to_iv(vol_quote.payoff, forward, price, ref_date; iv_guess=iv_guess)
end