"""
    volquote_from_deribit(data::Dict; use_mark=true)

Convert a Deribit option quote (as Dict) into a VolQuote.

# Arguments
- `data`: Dictionary containing Deribit quote fields
- `use_mark`: If true, use mark_price and mark_iv as mid values (default: true)

# Deribit Quote Fields
- `strike`: Strike price
- `expiry`: Expiry timestamp in milliseconds
- `option_type`: "C" for call, "P" for put
- `underlying_price`: Futures price for this expiry
- `mark_iv`: Mark implied volatility (percentage)
- `bid_price`, `ask_price`: Bid/ask prices (as fraction of underlying)
- `mark_price`: Mark price (as fraction of underlying)
- `ts`: Quote timestamp in milliseconds
- `bid_iv`, `ask_iv`: Optional bid/ask IVs (percentage)
- `last_price`: Last traded price (optional)
- `open_interest`: Open interest
- `volume`: Trading volume

# Returns
- `VolQuote` object

# Example
```julia
data = Dict(
    "strike" => 120000,
    "expiry" => 1766707200000,
    "option_type" => "C",
    "underlying_price" => 109449.27,
    "mark_iv" => 46.38,
    "bid_price" => 0.0415,
    "ask_price" => 0.042,
    "mark_price" => 0.04213933,
    "ts" => 1761153152332,
    "open_interest" => 7093.4,
    "volume" => 62.3
)
vq = volquote_from_deribit(data)
```
"""
function volquote_from_deribit(data::Dict; use_mark::Bool=true)
    # Parse basic fields
    strike = Float64(data["strike"])
    expiry = unix2datetime(data["expiry"] / 1000) + Hour(8)  # Convert ms to seconds and adjust to deribit settlement convention (8 AM UTC)
    timestamp = unix2datetime(data["ts"] / 1000)
    
    # Parse option type
    option_type = data["option_type"] == "C" ? Call() : Put()
    
    # Underlying price (futures price)
    underlying_price = Float64(data["underlying_price"])
    
    # Implied volatilities (convert from percentage to decimal)
    if use_mark
        mid_iv = Float64(data["mark_iv"]) / 100
    else
        # If not using mark, would need bid/ask IVs
        throw(ArgumentError("Non-mark IV handling not yet implemented"))
    end
    
    # Get bid/ask IVs if available
    bid_iv = haskey(data, "bid_iv") && !isnothing(data["bid_iv"]) ? 
             Float64(data["bid_iv"]) / 100 : NaN
    ask_iv = haskey(data, "ask_iv") && !isnothing(data["ask_iv"]) ? 
             Float64(data["ask_iv"]) / 100 : NaN
    
    # Prices (convert from fraction of underlying to absolute)
    mid_price = use_mark && haskey(data, "mark_price") && !isnothing(data["mark_price"]) ?
                Float64(data["mark_price"]) : NaN
    
    bid_price = haskey(data, "bid_price") && !isnothing(data["bid_price"]) ?
                Float64(data["bid_price"]) : NaN
    
    ask_price = haskey(data, "ask_price") && !isnothing(data["ask_price"]) ?
                Float64(data["ask_price"]) : NaN
    
    last_price = haskey(data, "last_price") && !isnothing(data["last_price"]) ?
                 Float64(data["last_price"]) : NaN
    
    # Market microstructure
    open_interest = haskey(data, "open_interest") && !isnothing(data["open_interest"]) ?
                    Float64(data["open_interest"]) : NaN
    
    volume = haskey(data, "volume") && !isnothing(data["volume"]) ?
             Float64(data["volume"]) : NaN
    
    # Construct VolQuote
    return VolQuote(
        strike,
        expiry,
        option_type,
        underlying_price,
        mid_iv,
        timestamp;
        underlying_type = FutureUnderlying,
        bid_iv = bid_iv,
        ask_iv = ask_iv,
        mid_price = mid_price,
        bid_price = bid_price,
        ask_price = ask_price,
        last_price = last_price,
        open_interest = open_interest,
        volume = volume,
        source = :deribit
    )
end