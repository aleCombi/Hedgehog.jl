### A Pluto.jl notebook ###
# v0.20.19

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 486b8480-235a-11f0-1d74-590ef52f1790
begin
	import Pkg
	Pkg.activate(".")  
	Pkg.instantiate()
end

# ╔═╡ d28428ae-bd56-4dd9-a08f-9c7616bdefc2
begin
	using Hedgehog
	using Dates
	today_date = Date(2025, 1, 1)
	expiry = Date(2026, 1, 1) # 1 year maturity
	strike = 100 # strike price K
	call_payoff = VanillaOption(strike, expiry, European(), Call(), Spot())
	put_payoff = VanillaOption(strike, expiry, European(), Put(), Spot())
end

# ╔═╡ 8e6e0554-babd-4727-9d3b-b4cf0742ca8b
begin
	using Plots
    # Spot price range
    S = 0:1:200

    # Evaluate payoffs
    call_values = call_payoff(S)
    put_values = put_payoff(S)

    # Plot call and put payoffs
    plot(S, call_values, label="Call Payoff", lw=2)
    plot!(S, put_values, label="Put Payoff", lw=2)
    xlabel!("Spot Price")
    ylabel!("Payoff")
    title!("European Option Payoffs (Strike = $strike)")
end

# ╔═╡ 4251d370-482b-4ff2-8973-b45348b4cbb5
md"# 📈 Black-Scholes Option Pricing"

# ╔═╡ 63440f9b-0621-4497-8ef7-1b9627994f75
md"In this notebook, we briefly introduce the Black-Scholes model for pricing European options.  
Our goal is to provide intuitive insights through simple plots and interactive graphic tools, leveraging the Hedgehog library."

# ╔═╡ a5b28346-5966-419d-96c9-60df7494e915
md"""
## Option Payoffs

Options are financial contracts that provide the right, but not the obligation, to buy or sell an asset at a specified strike price at a future time.

The payoff of a European call option is:

```math
\text{Call Payoff} = \max(S_T - K, 0)
```

The payoff of a European put option is:

```math
\text{Put Payoff} = \max(K - S_T, 0)
```

---

## Defining Payoffs in Hedgehog

Hedgehog defines option payoffs in a structured way, using types for:

- Exercise style (`European`, `American`)
- Call or put (`Call`, `Put`)
- Underlying (`Spot`, `Forward`)

The main type for simple options is `VanillaOption`.

"""


# ╔═╡ e28b1c34-08e3-4b18-be6c-fe390c771f32
md"""
---

## Evaluating a Payoff

Once created, a `VanillaOption` can be used like a function.

It accepts either a single spot price or an array of spot prices, returning the intrinsic value.

We use it to create a plot of intrinsic option value against the spot price.
---
"""

# ╔═╡ 46d9f60e-9a27-4807-af82-a1c8b33214f8
md"""
## No-Arbitrage Pricing and Risk-Neutral Measure

In a no-arbitrage setting, the fair price of a derivative is given by the **risk-neutral expectation** of its discounted payoff.

The **risk-neutral measure** is a probability measure under which all discounted asset prices are **martingales**. In other words, when discounted at the risk-free rate, asset prices have no drift beyond the risk-free return.

---

## Black-Scholes Model Dynamics

Under the risk-neutral measure, the price of the underlying asset is assumed to follow a **geometric Brownian motion**:

```math
dS_t = r S_t \, dt + \sigma S_t \, dW_t
```

where:
- ``S_t`` is the asset price at time $t$,
- ``r`` is the risk-free interest rate,
- ``\sigma`` is the constant volatility,
- ``W_t`` is a standard Brownian motion under the risk-neutral measure.

Under these assumptions, the asset price at maturity is **lognormally distributed**, allowing closed-form pricing formulas.

---

## Black-Scholes Pricing Formulas

For a European **call** option:

```math
\text{Call Price} = S_0 \Phi(d_1) - K e^{-rT} \Phi(d_2)
```

For a European **put** option:

```math
\text{Put Price} = K e^{-rT} \Phi(-d_2) - S_0 \Phi(-d_1)
```

where:

```math
d_1 = \frac{\ln(S_0/K) + (r + \sigma^2/2)T}{\sigma\sqrt{T}}
```

```math
d_2 = d_1 - \sigma\sqrt{T}
```

and $\Phi(\cdot)$ denotes the cumulative distribution function of the standard normal distribution.

---

## References

- Black, F., & Scholes, M. (1973). *The Pricing of Options and Corporate Liabilities*. Journal of Political Economy.
- Merton, R.C. (1973). *Theory of Rational Option Pricing*. Bell Journal of Economics and Management Science.

"""

# ╔═╡ af69e77a-e106-42de-9528-d685a94406ca
md"""
## Market Inputs and Pricing Problem Setup

To price an option using Hedgehog, we need to specify the market inputs:

- **Reference date**: The valuation date.
- **Spot price**: Current price of the underlying asset.
- **Risk-free rate**: Constant risk-free interest rate.
- **Volatility**: Constant implied volatility.

In Hedgehog, these are encapsulated in a `BlackScholesInputs` structure.
"""

# ╔═╡ c9a5e4fa-6856-423f-8a05-7fdddbbd727d
begin
	rate = 0.05
	spot = 100 # At-The-Money spot
	sigma = 0.4 # 40% volatility
	market_inputs = BlackScholesInputs(today_date, rate, spot, sigma)
end

# ╔═╡ 0bb9a5fc-6b98-457e-9bb6-24be786c4b11
md"""We then define two `PricingProblem` by combining the payoffs with the market inputs.
"""

# ╔═╡ a73c71b8-f061-47f7-8d57-695837a9375e
call_problem = PricingProblem(call_payoff, market_inputs)

# ╔═╡ ed49f12d-449d-4187-9619-98569020613f
put_problem = PricingProblem(put_payoff, market_inputs)

# ╔═╡ 4a09cbd6-1f60-423b-be6a-2b817a098f11
md"""
## Price and Sensitivities

Once the market inputs and the payoff have been defined, we can compute the **fair price** of the option under the Black-Scholes model.

In addition to the price itself, we are often interested in the **sensitivities** of the price with respect to various parameters, known as the **Greeks**:

- **Delta**: Sensitivity to changes in the spot price.
- **Vega**: Sensitivity to changes in volatility.
- **Rho**: Sensitivity to changes in the risk-free rate.
- **Gamma**: Sensitivity of Delta to changes in the spot price (second derivative).
- **Theta**: Sensitivity to the passage of time.

These sensitivities help traders understand and manage the risks associated with options.

In the next steps, we will compute both the option price and its Greeks using the Hedgehog library.
"""

# ╔═╡ dc1ac563-e493-4ad8-9c4e-52e5f4a1a8d0
md"""
In order to price options using the analytical formulas we showed, we can use the `BlackScholesAnalytic` pricing method, which is given as a second input to the `solve` function.
"""

# ╔═╡ 50b8a86b-9e1b-4817-833a-95b4e7546eff
put_price = solve(put_problem, BlackScholesAnalytic()).price

# ╔═╡ 6902b1a8-eb31-4d01-8071-40304565e030
call_price = solve(call_problem, BlackScholesAnalytic()).price

# ╔═╡ e0d4f0dc-5e21-4387-9f38-4385f3da6bb0
md"""
## Sensitivities: Greek Problems and Lenses

In Hedgehog, sensitivities (Greeks) are calculated by defining a **GreekProblem**.

A GreekProblem specifies:
- A **PricingProblem** (the option and market inputs we want to study),
- A **Lens** that tells us *which parameter* we want to differentiate with respect to.

### Lenses

A **Lens** is a simple object that knows:
- How to **read** a specific parameter from a pricing problem (like the spot price or volatility),
- How to **modify** that parameter while leaving everything else unchanged.

Lenses are based on the [Accessors.jl](https://github.com/JuliaObjects/Accessors.jl) package, which provides powerful tools for accessing and updating nested data structures.

For example:
- `SpotLens()` targets the spot price — used for Delta and Gamma.
- `VolLens(strike, expiry)` targets a specific volatility entry — used for Vega and Volga.

### Methods for Computing Greeks

Hedgehog supports different methods to compute Greeks:
- **AnalyticGreek**: Use closed-form formulas when available (fast and exact).
- **ForwardAD**: Automatic differentiation.
- **FiniteDifference**: Numerical finite differences (forward, backward, central schemes).

### Workflow Summary

To compute a Greek:
1. Define a `GreekProblem(pricing_problem, lens)`.
2. Choose a method (`AnalyticGreek()`, `ForwardAD()`, or `FiniteDifference()`).
3. Call `solve(greek_problem, method, pricing_method)`.

The result is the sensitivity of the option price with respect to the chosen parameter.

"""

# ╔═╡ 38417823-c778-47cc-b184-461e3f4dbef0
begin	
	pricing_method = BlackScholesAnalytic() # derivatives wrt analytic prices
	greek_method = AnalyticGreek() # use analytic greek formulas
	
    # Define lenses
    spot_lens = SpotLens()
    vol_lens = VolLens(1, 1)  # dummy indices (flat vol surface)

    # Solve for Call Delta and Vega
    call_delta = solve(GreekProblem(call_problem, spot_lens), greek_method, pricing_method)
    call_vega = solve(GreekProblem(call_problem, vol_lens), greek_method, pricing_method)

    # Solve for Put Delta and Vega
    put_delta = solve(GreekProblem(put_problem, spot_lens), greek_method, pricing_method)
    put_vega = solve(GreekProblem(put_problem, vol_lens), greek_method, pricing_method)

    # Print results
    println("European Call Delta: ", call_delta.greek)
    println("European Call Vega: ", call_vega.greek)
    println("European Put Delta: ", put_delta.greek)
    println("European Put Vega: ", put_vega.greek)
end

# ╔═╡ 7681bf7e-8b29-49b6-a452-c5ae66f943c9
begin
	using PlutoUI
	using Accessors
    # Define spot range
    spots = 0.0:1.0:200.0
    # Base market inputs
    base_inputs = BlackScholesInputs(today_date, rate, 100.0, 0.4)
    base_problem = PricingProblem(call_payoff, base_inputs)
    
    # Function factory that creates pricing and Greek functions parameterized by vol
    function get_price_at_spot(problem, vol)
        # Base market inputs with the slider value
        mod_problem = set(problem, vol_lens, vol)
        
        # Price function that takes a spot value and returns the price
        price_at_spot(s) = solve(set(mod_problem, spot_lens, s), BlackScholesAnalytic()).price
        
        return price_at_spot
    end

	function get_greek_at_spot(problem, vol, greek_lens)
		# Base market inputs with the slider value
        modified_problem = set(problem, vol_lens, vol)
		# Greek function that takes a spot value and returns the requested Greek
        greek_at_spot(s) = 
            solve(GreekProblem(set(modified_problem, spot_lens, s), greek_lens), 
                  AnalyticGreek(), BlackScholesAnalytic()).greek

		return greek_at_spot       
	end

		function get_fd_greek_at_spot(problem, vol, greek_lens, fd_bump)
		# Base market inputs with the slider value
        modified_problem = set(problem, vol_lens, vol)
		# Greek function that takes a spot value and returns the requested Greek
        greek_at_spot(s) = 
            solve(GreekProblem(set(modified_problem, spot_lens, s), greek_lens), 
                  FiniteDifference(fd_bump), BlackScholesAnalytic()).greek

		return greek_at_spot       
	end
end

# ╔═╡ e485fff0-71a7-46fb-af1c-923ec0d99e36
md"""
## Graphic Insights

Pricing formulas and sensitivities provide a detailed mathematical view of option behavior.  
However, visualizing these relationships gives an even stronger intuition.

In this section, we use interactive plots and sliders to explore:

- How **option prices** vary with spot and volatility,
- How **Delta** and **Vega** evolve with changing market conditions.

By adjusting spot prices and volatilities dynamically, we can build a concrete, visual understanding of option risk profiles.

All plots are powered by Hedgehog's flexible architecture and Pluto's interactivity features.
"""

# ╔═╡ 07783212-6a2e-4ac2-934c-faf25eb74142
md"""
### Option Price, Delta, and Vega vs Spot

We first explore how the option price, Delta, and Vega change as a function of the **spot price**.

You can adjust the **volatility** using the sliders above each plot to see how higher or lower implied volatilities impact the curves.
"""

# ╔═╡ fba78c77-5baf-47f7-a789-cd020bb91a53
md"### Price Plot Volatility
Below you can see how a call price changes with the spot price. When the spot price is below the strike price the option is said In-The-Money (ITM), when it is equal it is said At-The-Money (ATM), when it is above it is said Out-of-The-Money (OTM).
Recall that the strike price is fixed at 100. 
One can see that the option price is a convex function of the spot.
Playing with the volatility slider you can see how with low volatilities the graph resembles the payoff graphs, while with high volatilities the graph looks like a straight line, with the option price equaling the spot price. 
"

# ╔═╡ b007b80f-9da9-4f8b-ad32-5bce4dae0d97
@bind vol_slider_price Slider(0.01:0.01:1.8, default=0.2)

# ╔═╡ 677008f9-afb0-45c9-b29e-e1b5fba2341d



# ╔═╡ 46b114ab-954a-4e64-b69c-9dc33607feb0
begin
	price_at_spot = get_price_at_spot(base_problem, vol_slider_price)
	call_prices = price_at_spot.(spots)
	# Create individual plots
    p1 = plot(spots, call_prices, label="Call Price", lw=2)
    xlabel!(p1, "Spot Price")
    ylabel!(p1, "Value")
    title!(p1, "Option Price vs Spot (Volatility = $(round(vol_slider_price * 100))%)")
end

# ╔═╡ 68cae9fd-909f-4618-ac61-2151f11d182f
md"### Delta Plot Volatility
Below a similar graph is plotted for the delta. 
The delta is also an increasing function of the spot price.
"

# ╔═╡ 7582c0e6-7c44-42d1-9db4-260bcff044c6
@bind vol_slider_delta Slider(0.001:0.01:0.8, default=0.2)

# ╔═╡ 6c58f48a-b9e0-405c-87b2-da7a02eab9b2
@bind bump Slider(0.000000000001:0.00001:0.8, default=0.2)

# ╔═╡ b669d785-f5d6-4f07-b836-f64eb2bf0775
bump

# ╔═╡ 178eaf5d-74c8-4e48-bb96-5f8c0c97058c
begin
	delta_at_spot = get_greek_at_spot(base_problem, vol_slider_delta, spot_lens)
	call_deltas = delta_at_spot.(spots)
	# Create a NEW plot object for Delta
    p2 = plot(spots, delta_at_spot, label="Call Delta", lw=2)
    xlabel!(p2, "Spot Price") # Modify p2's labels
    ylabel!(p2, "Delta")
    title!(p2, "Option Delta vs Spot (Volatility = $(round(vol_slider_delta * 100))%)")
	delta_at_spot_fd = get_fd_greek_at_spot(base_problem, vol_slider_delta, spot_lens, bump)
    p21 = plot!(spots, delta_at_spot_fd, label="Call Delta", lw=2)

end

# ╔═╡ f02c1a0f-a30e-4f83-9fbe-8d93a2a80dc4
md"### Vega Plot Volatility
Below a similar graph is plotted for the vega. 
Note the bell shape, with high vegas at ATM options, with low vegas at extreme values. 
This is expected, as with extreme values the price is dominated by the instrinsic option value.
Also see how increasing the volatility makes the bell larger.
"

# ╔═╡ 24aeee97-c9da-468a-8456-b3c94d61414f
@bind vol_slider_vega Slider(0.1:0.01:0.8, default=0.2)

# ╔═╡ 6384de4a-5c6e-4693-9334-6f7810d8fc2d
begin
	vega_at_spot = get_greek_at_spot(base_problem, vol_slider_vega, vol_lens)
	call_vegas = vega_at_spot.(spots)
	# Create individual plots
    p3 = plot(spots, call_vegas, label="Call Delta", lw=2)
    xlabel!(p3, "Spot Price")
    ylabel!(p3, "Vega")
    title!(p3, "Option Vega vs Spot (Volatility = $(round(vol_slider_vega * 100))%)")
end

# ╔═╡ 71f631b5-30e4-4bc8-aff3-c54aa6042f05


# ╔═╡ Cell order:
# ╠═486b8480-235a-11f0-1d74-590ef52f1790
# ╟─4251d370-482b-4ff2-8973-b45348b4cbb5
# ╟─63440f9b-0621-4497-8ef7-1b9627994f75
# ╟─a5b28346-5966-419d-96c9-60df7494e915
# ╠═d28428ae-bd56-4dd9-a08f-9c7616bdefc2
# ╟─e28b1c34-08e3-4b18-be6c-fe390c771f32
# ╠═8e6e0554-babd-4727-9d3b-b4cf0742ca8b
# ╟─46d9f60e-9a27-4807-af82-a1c8b33214f8
# ╟─af69e77a-e106-42de-9528-d685a94406ca
# ╠═c9a5e4fa-6856-423f-8a05-7fdddbbd727d
# ╟─0bb9a5fc-6b98-457e-9bb6-24be786c4b11
# ╠═a73c71b8-f061-47f7-8d57-695837a9375e
# ╠═ed49f12d-449d-4187-9619-98569020613f
# ╟─4a09cbd6-1f60-423b-be6a-2b817a098f11
# ╟─dc1ac563-e493-4ad8-9c4e-52e5f4a1a8d0
# ╠═50b8a86b-9e1b-4817-833a-95b4e7546eff
# ╠═6902b1a8-eb31-4d01-8071-40304565e030
# ╟─e0d4f0dc-5e21-4387-9f38-4385f3da6bb0
# ╠═38417823-c778-47cc-b184-461e3f4dbef0
# ╟─e485fff0-71a7-46fb-af1c-923ec0d99e36
# ╟─07783212-6a2e-4ac2-934c-faf25eb74142
# ╠═7681bf7e-8b29-49b6-a452-c5ae66f943c9
# ╟─fba78c77-5baf-47f7-a789-cd020bb91a53
# ╠═b007b80f-9da9-4f8b-ad32-5bce4dae0d97
# ╠═677008f9-afb0-45c9-b29e-e1b5fba2341d
# ╠═46b114ab-954a-4e64-b69c-9dc33607feb0
# ╠═68cae9fd-909f-4618-ac61-2151f11d182f
# ╠═7582c0e6-7c44-42d1-9db4-260bcff044c6
# ╠═6c58f48a-b9e0-405c-87b2-da7a02eab9b2
# ╠═b669d785-f5d6-4f07-b836-f64eb2bf0775
# ╠═178eaf5d-74c8-4e48-bb96-5f8c0c97058c
# ╟─f02c1a0f-a30e-4f83-9fbe-8d93a2a80dc4
# ╠═24aeee97-c9da-468a-8456-b3c94d61414f
# ╠═6384de4a-5c6e-4693-9334-6f7810d8fc2d
# ╠═71f631b5-30e4-4bc8-aff3-c54aa6042f05
