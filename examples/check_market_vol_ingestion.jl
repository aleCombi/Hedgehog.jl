using Revise, Parquet2
using DataFrames
using Dates
using Hedgehog, Plots

# Load quotes and create surface
filepath = "C:/repos/DeribitVols/data/downloaded/all_20251022-192655/20251022-171234Z/data_parquet/deribit_chain/date=2025-10-22/underlying=BTC/batch_20251022-171234340988.parquet"
surface = Hedgehog.marketvolsurface_from_deribit_parquet(filepath)

# Print surface info
println("=== Market Vol Surface Info ===")
println("Number of quotes: ", length(surface.quotes))
println("Reference date: ", Dates.epochms2datetime(surface.reference_date))
println("Underlying info type: ", typeof(surface.underlying_info))

if surface.underlying_info isa Hedgehog.FuturesBasedInfo
    curve = surface.underlying_info.futures_curve
    println("Futures curve points: ", length(curve))
    forwards = Hedgehog.spine_forwards(curve)
    println("First futures price: ", forwards[1])
    println("Last futures price: ", forwards[end])
elseif surface.underlying_info isa Hedgehog.SpotBasedInfo
    println("Spot: ", surface.underlying_info.spot)
end

println("\n=== First 5 Quotes ===")
for (i, vq) in enumerate(surface.quotes[1:min(5, length(surface.quotes))])
    println("\nQuote $i:")
    println("  Strike: ", vq.payoff.strike)
    println("  Expiry: ", Dates.epochms2datetime(vq.payoff.expiry))
    println("  Type: ", vq.payoff.call_put)
    println("  Underlying price: ", vq.underlying_price)
    println("  Mid IV: ", round(vq.mid_iv * 100, digits=2), "%")
    println("  Mid price: ", vq.mid_price, " BTC")
    println("  Timestamp: ", Dates.epochms2datetime(vq.timestamp))
end
p2d = Hedgehog.plot_vol_2d_by_expiry(surface; field=:mid_iv, show_bid_ask=true, max_expiries=8)
p3d = Hedgehog.plot_vol_surface_3d(surface; field=:all)

plot(p2d)  # or display however you want
plot(p3d)
