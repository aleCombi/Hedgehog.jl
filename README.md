# Hedgehog

**Hedgehog** is a modular, SciML-inspired derivatives pricing library in Julia.

[![Build Status](https://github.com/aleCombi/Hedgehog.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/aleCombi/Hedgehog.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://alecombi.github.io/Hedgehog.jl/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 📐 Design Overview

All pricing and calibration workflows follow a SciML-inspired `solve(problem, method)` interface.

To compute a price, you define a `PricingProblem` using:

- A **payoff** (e.g. European call, American put)
- A set of **market inputs** (e.g. Black-Scholes inputs, Heston inputs)
- Then solve it with a **pricing method** (e.g. Monte Carlo, analytical formula, Fourier inversion)

```julia
payoff = VanillaOption(...)
market = BlackScholesInputs(...)
problem = PricingProblem(payoff, market)

sol = solve(problem, BlackScholesAnalytic())
price = sol.price
```

## ✅ Supported Payoffs

- European Call / Put
- American Call / Put

## 🧠 Supported Models (Price Dynamics)

- Black-Scholes (`LognormalDynamics`)
- Heston (`HestonDynamics`)

## ⚙️ Pricing Methods

- Analytical formulas (Black-Scholes)
- Binomial Trees (Cox–Ross–Rubinstein)
- Monte Carlo:
  - Euler–Maruyama
  - Exact simulation (Black-Scholes, Broadie–Kaya for Heston)
- Fourier methods (Carr–Madan)

## 📊 Calibration

Hedgehog supports calibration via a unified interface:

- Solve for implied volatility using `CalibrationProblem`
- Invert volatility surfaces
- Build fully calibrated `RectVolSurface` objects from price matrices

## 🧮 Sensitivities

- Greeks supported via a `GreekProblem` interface:
  - Finite differences
  - Automatic differentiation
  - `BatchGreekProblem` to compute a full gradient of sensitivities

## 🚀 Highlights

- Modular by construction: models, payoffs, and methods are swappable
- Unified `solve(problem, method)` interface across pricing and calibration
- Inspired by the SciML architecture and ecosystem
- Built on top of SciML components (StochasticDiffEq.jl, NonlinearSolve.jl, Integrals.jl)
- Open-source and focused on prototyping cutting-edge methods

## 📦 Dependencies

Hedgehog is built on several high-quality Julia packages:

- [SciML Ecosystem](https://sciml.ai/): 
  - [StochasticDiffEq.jl](https://github.com/SciML/StochasticDiffEq.jl) - For stochastic simulation
  - [NonlinearSolve.jl](https://github.com/SciML/NonlinearSolve.jl) - For calibration and implied volatility
  - [Integrals.jl](https://github.com/SciML/Integrals.jl) - For Fourier-based pricing methods
  - [Optimization.jl](https://github.com/SciML/Optimization.jl) - For advanced calibration
  - [DataInterpolations.jl](https://github.com/SciML/DataInterpolations.jl) - For volatility surfaces and rate curves

- [ForwardDiff.jl](https://github.com/JuliaDiff/ForwardDiff.jl) - Automatic differentiation for Greeks calculation
- [Accessors.jl](https://github.com/JuliaObjects/Accessors.jl) - Functional lens-based access for Greeks and calibration
- [Distributions.jl](https://github.com/JuliaStats/Distributions.jl) - For statistical distributions and sampling

## 📖 Documentation

Complete documentation is available at [https://alecombi.github.io/Hedgehog.jl/](https://alecombi.github.io/Hedgehog.jl/)

## 🔍 Examples

Example scripts demonstrating Hedgehog's functionality can be found in the `examples/` directory:

- `examples/` - Standalone Julia scripts for various pricing scenarios
- `examples/notebooks/` - Pluto notebooks for interactive exploration (in progress)

These examples cover various use cases from basic option pricing to calibration scenarios and are designed to help you get started with the library.

## 🔍 Related Packages

Hedgehog.jl builds on the ideas and complements a number of Julia packages for derivatives pricing. Here's how it compares:

### 🧰 [FinancialDerivatives.jl](https://github.com/JuliaQuant/FinancialDerivatives.jl)

Implements classic models like Black-Scholes and binomial trees for vanilla options, with support for asian options too, which are not available in Hedgehog yet. Hedgehog aims at extending these ideas with automatic differentiation, calibration tools, and a modular problem-method interface.

### 🧰 [CharFuncPricing.jl](https://github.com/s-broda/CharFuncPricing.jl)

Focused on Fourier-based pricing under models like Heston. It implements COS method, which is not in Hedgehog at the moment. Hedgehog includes characteristic function methods too with Carr-Madan, including them within a broader framework for simulation, calibration, and AD/FD sensitivities.

### 🧰 [AQFED.jl](https://github.com/jherekhealy/AQFED.jl)

A deep and ambitious package accompanying a book on equity derivatives. Covers topics like basket options and rough paths. It has a deep coverage of cutting-edge methods. Hedgehog aims for a more modular and general-purpose architecture, designed for reuse and extensibility.

### 🧰 [Bruno.jl](https://github.com/USU-Analytics-Solution-Center/Bruno.jl)

A promising package combining simulation, pricing, and delta hedging. However, it hasn’t been updated in over two years. Hedgehog is under active development and structured for long-term flexibility.

### 🧰 [QuantLib.jl](https://github.com/pazzo83/QuantLib.jl)

A pure Julia port of the C++ QuantLib library. It offers broad model coverage but hasn’t been active in the last 5 years. Hedgehog focuses on modern Julia design, composability, and integration with scientific computing tools.

---

## 🦤 What Makes Hedgehog.jl Different?

* **Modular design** with SciML-style `solve(problem, method)` interface
* **Automatic and finite difference Greeks**, with lens-based parameter access (`Accessors.jl`)
* **Built on Julia’s scientific stack**, including `DifferentialEquations.jl`
* **Actively developed** with extensibility and composability as core design goals

Hedgehog aims to provide a clean, Julia-native foundation for derivatives pricing, sensitivities, and calibration — suited for research, prototyping, and production use.

## 👥 Collaboration

Contributions are welcome! If you have ideas for new features, models, or improvements, feel free to open an issue or submit a pull request.

You can also reach out to Alessandro Combi via the Julia Zulip chat for questions or discussion.
