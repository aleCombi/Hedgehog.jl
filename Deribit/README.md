# Deribit Library

A modular Julia library for calibrating the Heston stochastic volatility model to Deribit BTC options data, with comprehensive validation and mispricing detection capabilities.

## Overview

This library refactors the original monolithic scripts into a clean, reusable structure with separation of concerns.

## Library Structure

```
├── data_loading.jl               # Parquet file discovery & loading
├── validation_scheduling.jl      # Time period parsing & scheduling
├── calibration.jl                # Heston calibration wrapper
├── fit_statistics.jl             # Goodness-of-fit metrics
├── mispricing.jl                 # Mispricing detection & islands
├── visualization.jl              # All plotting functions
├── config.jl                     # Config loading utilities
├── Deribit.jl          # Main module (exports everything)
├── calibrate_and_validate.jl    # Main calibration script
├── analyze_mispricings.jl       # Mispricing analysis script
└── README.md
```

## Quick Start

### Run calibration and validation:
```bash
julia calibrate_and_validate.jl
```

### Run mispricing analysis:
```bash
julia analyze_mispricings.jl
```

## Module Documentation

See inline docstrings for detailed documentation of all functions.

### Key Features

✅ Modular design - Each file has a single responsibility  
✅ Reusable functions - No code duplication  
✅ Config-driven - All parameters in YAML  
✅ Hedgehog integration - Uses existing types  
✅ Clean I/O - Separate compute from save/print  
✅ Duplicate detection - Avoids reprocessing same snapshots  
✅ Flexible scheduling - Three validation modes  
✅ Rich visualization - Multiple plot types  
✅ Island detection - Find isolated mispricings  

## Requirements

- Julia 1.x
- Hedgehog.jl
- DataFrames, Plots, CSV, YAML