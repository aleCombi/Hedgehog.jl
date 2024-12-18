"""
    RateFixingSource

An abstract type representing a source of past fixings for an interest rate index.
It could be a simple in-memory dictionary, a csv file, a database etc.
"""
abstract type RateFixingSource end

"""
    RateFixingTuples <: RateFixingSource

A struct to store fixings for an interest rate index in an ImmutableDict.
"""
struct RateFixingTuples <: RateFixingSource
    fixings::Base.ImmutableDict
end 

"""
    get_fixing(date, fixing_source::RateFixingTuples)

# Arguments
- `date`: Start date of the interest rate index period.
- `fixing_source`: Source of the interest rate fixings.

# Returns
- Fixing at the specified date.
"""
function get_fixing(date, fixing_source::RateFixingTuples)
    return fixing_source.fixings[date]
end

"""
    MarketData

Abstract type representing Market Data objects necessary to price a specified set of cash flows.
"""
abstract type MarketData end

"""
    RateMarketData{R<:AbstractRateCurve, F<:RateFixingSource, I<:AbstractRateIndex} <: MarketData

"""
struct RateMarketData{R<:AbstractRateCurve, F<:RateFixingSource, I<:AbstractRateIndex} <: MarketData
    rate_index::I
    rate_curve::R
    fixing_source::F
end

function market_data_date(market_data::RateMarketData)
    return market_data.rate_curve.date
end

function RateMarketData(rate_curve::R) where {R<:AbstractRateCurve}
    return RateMarketData(
        RateIndex("Index"),
        rate_curve, 
        RateFixingTuples(Base.ImmutableDict{Date, Float64}()))
end