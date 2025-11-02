using JSON

# Parse the JSON string
json_str = """{"instrument_name":"BTC-26DEC25-120000-C","underlying":"BTC","expiry":1766707200000,"strike":120000,"option_type":"C","bid_price":0.0415,"ask_price":0.042,"last_price":null,"mark_price":0.04213933,"mark_iv":46.38,"open_interest":7093.4,"volume":62.3,"underlying_price":109449.27,"ts":1761153152332,"date":"2025-10-22","row_id":"5ecc65bc26d1dba58c7a47948bebdda7a65ca314"}"""

data = JSON.parse(json_str)

# Convert to VolQuote
vq = Hedgehog.volquote_from_deribit(data)

# Inspect the result
println("Strike: $(vq.payoff.strike)")
println("Expiry: $(Dates.unix2datetime(vq.payoff.expiry/1000))")
println("Option type: $(vq.payoff.call_put)")
println("Underlying price: $(vq.underlying_price)")
println("Mid IV: $(vq.mid_iv)")
println("Mid price: $(vq.mid_price)")
println("Bid price: $(vq.bid_price)")
println("Ask price: $(vq.ask_price)")
println("Open interest: $(vq.open_interest)")
println("Volume: $(vq.volume)")
println("Source: $(vq.source)")


# This should output:
# 
# Strike: 120000.0
# Expiry: 2025-12-26T08:00:00
# Option type: Call()
# Underlying price: 109449.27
# Mid IV: 0.4638
# Mid price: 4611.976...
# Bid price: 4542.244...
# Ask price: 4596.868...
# Open interest: 7093.4
# Volume: 62.3
# Source: deribit
# ```