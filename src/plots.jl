# == Plots ==
using Dates
using DataFrames
using TimeZones
using Plots

"""
    heatmap_hours(df::DataFrame; tz::TimeZone=tz"UTC",
                  title::AbstractString="Weekly Occupancy Heatmap")

Plot a weekday × hour heatmap of busy minutes.
"""
function heatmap_hours(df::DataFrame; tz::TimeZone=tz"UTC",
                       title::AbstractString="Weekly Occupancy Heatmap")
    occ = occupancy_table(df; by=:hour, tz=tz)
    # Build matrix 7×24 (Mon=1..Sun=7)
    M = fill(0.0, 7, 24)
    for r in eachrow(occ)
        M[r.weekday, r.hour+1] = r.busy_minutes
    end
    return heatmap(0:23, 1:7, M;
        xlabel="Hour",
        ylabel="Weekday (Mon=1)",
        colorbar_title="Busy (min)",
        title=title)
end





"""
    plot_timeline(df::DataFrame; tz::TimeZone=tz"UTC", title::AbstractString="Event Timeline") -> Plots.Plot

Render a Gantt-like timeline of events. The x-axis auto-zooms to the earliest start
and latest end in `df` (evaluated in `tz`). The y-axis lists events by index and
labels rows by `:summary` if available, otherwise by `:uid`.

# Arguments
- `df::DataFrame`: Must contain `:dtstart` and `:dtend` (`ZonedDateTime`); optional `:summary`, `:uid`.

# Keywords
- `tz::TimeZone` = `tz"UTC"`: Timezone for converting and displaying times.
- `title::AbstractString` = `"Event Timeline"`: Figure title.

# Examples
julia> plot_timeline(df)
julia> plot_timeline(df; tz=tz"Europe/Istanbul", title="Sprint Schedule")
"""
function plot_timeline(df::DataFrame; tz::TimeZone=tz"UTC", title::AbstractString="Event Timeline")
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)

    if nrow(d) == 0
        return plot(title="No events")
    end

    d = sort(d, :dtstart)
    d[!, :row] = 1:nrow(d)


    tmin = minimum(d.dtstart)
    tmax = maximum(d.dtend)
    xlo  = DateTime(tmin) # + Minute(0)
    xhi  = DateTime(tmax) # + Minute(0)

    cols = fill(:steelblue, nrow(d))
    plt = plot(; legend=false, xlabel="Time ($(tz))", ylabel="Event index", xlims=(xlo, xhi), title=title)
    for r in eachrow(d)
        plot!([DateTime(r.dtstart), DateTime(r.dtend)], [r.row, r.row]; lw=8, color=cols[r.row])
    end
    yticks!(1:nrow(d), string.(coalesce.(d.summary, d.uid)))
    return plt
end




"""
    plot_conflicts(df::DataFrame; tz::TimeZone=tz"UTC", title::AbstractString="Event Conflicts Timeline") -> Plots.Plot

Render a timeline that highlights overlapping (conflicting) events in **red** and
non-conflicting events in **gray**. The x-axis auto-zooms to the min–max range of
conflicting events; if there are no conflicts, it spans the full event range (all in `tz`).

# Arguments
- `df::DataFrame`: Must include `:dtstart` and `:dtend` (`ZonedDateTime`); optional `:summary`, `:uid`.

# Keywords
- `tz::TimeZone` = `tz"UTC"`: Timezone used to convert and evaluate event times.
- `title::AbstractString` = `"Event Conflicts Timeline"`: Figure title.

# Examples
julia> plot_conflicts(df)
julia> plot_conflicts(df; tz=tz"Europe/Istanbul", title="Overlap Check")
"""
function plot_conflicts(df::DataFrame; tz::TimeZone=tz"UTC", title::AbstractString="Event Conflicts Timeline")
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)

    if nrow(d) == 0
        return plot(title="No events")
    end

    # Find conflicts
    conf = conflicts(d)
    has_conf = Dict(u => false for u in d.uid)
    for r in eachrow(conf)
        has_conf[r.uid1] = true
        has_conf[r.uid2] = true
    end

    d = sort(d, :dtstart)
    d[!, :row] = 1:nrow(d)

    tmin = minimum(d.dtstart)
    tmax = maximum(d.dtend)
    xlo  = DateTime(tmin) # + Minute(0)
    xhi  = DateTime(tmax) # + Minute(0)
    xlo = DateTime(tmin);  xhi = DateTime(tmax)

    plt = plot(; legend=false, xlabel="Time ($(tz))", ylabel="Event index", xlims=(xlo, xhi),title=title)
    for r in eachrow(d)
        color = get(has_conf, r.uid, false) ? :red : :gray
        plot!([DateTime(r.dtstart), DateTime(r.dtend)], [r.row, r.row]; lw=8, color=color)
    end
    yticks!(1:nrow(d), string.(coalesce.(d.summary, d.uid)))
    return plt
end

