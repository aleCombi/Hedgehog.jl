# Deribit.jl
# Main module for Heston calibration and validation

module Deribit

using Dates
using DataFrames
using Statistics
using Printf
using CSV
using YAML
using Plots
using Hedgehog

# Include all submodules
include("data_loading.jl")
include("validation_scheduling.jl")
include("calibration.jl")
include("fit_statistics.jl")
include("mispricing.jl")
include("visualization.jl")
include("config.jl")
include("butterfly_analysis.jl")

# Export data loading functions
export extract_file_dt,
       find_parquet_file,
       load_market_data

# Export validation scheduling functions
export parse_datetime,
       parse_period,
       period_ms,
       format_delta_label,
       generate_validation_times

# Export calibration functions and types
export DeribitResult,
       calibrate_heston,
       to_heston_inputs,
       print_calibration_summary,
       save_calibration_params,
       get_param_tuple

# Export fit statistics functions and types
export FitStatistics,
       compute_fit_statistics,
       print_fit_summary,
       save_fit_summary_csv,
       save_fit_detailed_csv,
       save_all_detailed_csvs

# Export mispricing functions and types
export MispricingRecord,
       detect_mispricings,
       find_islands,
       records_to_dataframe,
       save_mispricing_csv,
       save_islands_csvs,
       print_mispricing_summary,
       print_top_mispricings

# Export visualization functions
export plot_vol_rmse_over_time,
       plot_vol_error_histogram,
       plot_market_vs_model_scatter,
       plot_rmse_comparison_bar,
       plot_validation_summary,
       save_validation_plots,
       plot_mispricing_heatmap,
       plot_mispricing_heatmaps,
       save_mispricing_heatmaps

# Export config functions
export load_config,
       extract_filter_params,
       extract_iv_config,
       extract_calibration_config,
       extract_validation_config,
       extract_mispricing_config,
       get_selection_mode,
       get_pricing_method,
       create_run_folder,
       save_config_copy,
       get_plot_size

export ButterflyReversion, save_butterfly_analysis, print_butterfly_summary
end # module