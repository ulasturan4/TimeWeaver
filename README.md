# TimeWeaver

Analyze calendar (.ics) files in Julia: detect conflicts, compute daily/hourly occupancy & stress, run what‑if checks, and plot timelines/heatmaps.

## Installation
```julia
pkg> activate .
pkg> instantiate
```

## Quick Start
```julia
using TimeWeaver, TimeZones, Plots
df = load_ics("data/mycalendar.ics")
normalize_timezone!(df, tz"Europe/Istanbul")
display(plot_timeline(df; tz=tz"Europe/Istanbul"))
display(heatmap_hours(df; tz=tz"Europe/Istanbul"))
```
See `docs/ProjectBook.md` for a complete tour.
