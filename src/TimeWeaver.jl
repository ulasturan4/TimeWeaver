module TimeWeaver

using DataFrames
using Dates
using TimeZones
using Statistics
using Plots

include("io.jl")
include("conflicts.jl")
include("stress.jl")
include("whatif.jl")
include("plots.jl")
include("schedule.jl")
include("docstrings.jl")

export load_ics, normalize_timezone!,
       conflicts, find_overloads,
       occupancy_table, stress_index,
       simulate_event,
       heatmap_hours, plot_timeline, plot_conflicts, conflict_timeline,
       filter_events, utilization

end # module