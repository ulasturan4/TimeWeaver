
using Dates, DataFrames, TimeZones

@doc raw"""
    conflicts(df::DataFrame)

Detect pairwise overlaps between events.

**Examples**

```julia
julia> using TimeWeaver, DataFrames, TimeZones, Dates
julia> tz = tz"Europe/Istanbul";
julia> df = DataFrame(uid=["a","b"],
                      summary=["Meet A","Meet B"],
                      dtstart=[ZonedDateTime(2025,9,2,10,0,0,tz),
                               ZonedDateTime(2025,9,2,10,30,0,tz)],
                      dtend=[ZonedDateTime(2025,9,2,11,0,0,tz),
                             ZonedDateTime(2025,9,2,11,15,0,tz)]);
julia> TimeWeaver.conflicts(df) |> nrow
1
```

```julia
julia> TimeWeaver.conflicts(df[1:1, :]) |> nrow  # single event → no conflicts
0
```
""" conflicts

@doc raw"""
    find_overloads(df::DataFrame; threshold::Period=Minute(15))

Mark time windows where concurrent load exceeds `threshold`.

**Examples**

```julia
julia> using TimeWeaver, DataFrames, TimeZones, Dates
julia> tz = tz"Europe/Istanbul";
julia> df = DataFrame(uid=["a","b"],
                      summary=["A","B"],
                      dtstart=[ZonedDateTime(2025,9,2,9,0,0,tz),
                               ZonedDateTime(2025,9,2,9,20,0,tz)],
                      dtend=[ZonedDateTime(2025,9,2,9,15,0,tz),
                             ZonedDateTime(2025,9,2,9,35,0,tz)]);
julia> TimeWeaver.find_overloads(df; threshold=Minute(10)) |> nrow
1
```

```julia
julia> TimeWeaver.find_overloads(df; threshold=Minute(1)) |> nrow
0
```
""" find_overloads

@doc raw"""
    load_ics(path::AbstractString) -> DataFrame

Load an .ics file into a tidy `DataFrame` with at least `:uid, :summary, :dtstart, :dtend`.

**Examples**

```julia
julia> using TimeWeaver
julia> df = load_ics("data/mycalendar.ics");  # sample file provided in repo
julia> all(∈([:uid,:summary,:dtstart,:dtend], names(df)))
true
```

```julia
julia> size(df)[2] ≥ 4
true
```
""" load_ics

@doc raw"""
    normalize_timezone!(df::DataFrame, tz::TimeZone)

Convert all datetime fields to the target timezone in-place.

**Examples**

```julia
julia> using TimeWeaver, TimeZones
julia> df = load_ics("data/mycalendar.ics");
julia> normalize_timezone!(df, tz"Europe/Istanbul");  # should not error
nothing
```

```julia
julia> all(x-> x.zone == tz"Europe/Istanbul", df.dtstart) &&
       all(x-> x.zone == tz"Europe/Istanbul", df.dtend)
true
```
""" normalize_timezone!

@doc raw"""
    occupancy_table(df::DataFrame; by=:day, tz::TimeZone)

Aggregate busy minutes by day or by (weekday,hour).

**Examples**

```julia
julia> using TimeWeaver, DataFrames, TimeZones, Dates
julia> tz = tz"Europe/Istanbul";
julia> df = DataFrame(uid=["a"], summary=["Focus"],
                      dtstart=[ZonedDateTime(2025,9,3,9,0,0,tz)],
                      dtend=[ZonedDateTime(2025,9,3,10,0,0,tz)]);
julia> occd = occupancy_table(df; by=:day, tz=tz);
julia> all(∈([:date,:busy_minutes], names(occd)))
true
```

```julia
julia> occh = occupancy_table(df; by=:hour, tz=tz);
julia> all(∈([:weekday,:hour,:busy_minutes], names(occh)))
true
```
""" occupancy_table

@doc raw"""
    stress_index(df::DataFrame; by=:day, tz::TimeZone)

Return a table with busy minutes and a 0–100 stress measure.

**Examples**

```julia
julia> using TimeWeaver, TimeZones
julia> s = stress_index(load_ics("data/mycalendar.ics"); by=:day, tz=tz"Europe/Istanbul");
julia> all(∈([:busy_minutes,:stress], names(s)))
true
```

```julia
julia> minimum(s.stress) ≥ 0 && maximum(s.stress) ≤ 100
true
```
""" stress_index

@doc raw"""
    heatmap_hours(df::DataFrame; tz::TimeZone, title="Busy Minutes by Weekday & Hour")

Return a heatmap figure (7×24) of busy minutes.

**Examples**

```julia
julia> using TimeWeaver, TimeZones, Plots
julia> tz = tz"Europe/Istanbul";
julia> plt = heatmap_hours(load_ics("data/mycalendar.ics"); tz=tz);
julia> typeof(plt) <: Any
true
```

```julia
julia> display(plt);  # visual check
```
""" heatmap_hours

@doc raw"""
    plot_timeline(df::DataFrame; tz::TimeZone)

Plot events on a timeline.

**Examples**

```julia
julia> using TimeWeaver, TimeZones, Plots
julia> tz = tz"Europe/Istanbul";
julia> t = plot_timeline(load_ics("data/mycalendar.ics"); tz=tz);
julia> typeof(t) <: Any
true
```

```julia
julia> display(t);
```
""" plot_timeline

@doc raw"""
    plot_conflicts(df::DataFrame; tz::TimeZone)

Plot detected conflicts on a timeline.

**Examples**

```julia
julia> using TimeWeaver, TimeZones, Plots, DataFrames, Dates
julia> tz = tz"Europe/Istanbul";
julia> df = DataFrame(uid=["a","b"], summary=["A","B"],
                      dtstart=[ZonedDateTime(2025,9,2,10,0,0,tz),
                               ZonedDateTime(2025,9,2,10,30,0,tz)],
                      dtend=[ZonedDateTime(2025,9,2,11,0,0,tz),
                             ZonedDateTime(2025,9,2,11,15,0,tz)]);
julia> display(plot_conflicts(df; tz=tz));
```
""" plot_conflicts

@doc raw"""
    conflict_timeline(df::DataFrame; tz::TimeZone)

Plot only the conflicting segments across events.

**Examples**

```julia
julia> using TimeWeaver, TimeZones, Plots
julia> tz = tz"Europe/Istanbul";
julia> ct = conflict_timeline(load_ics("data/mycalendar.ics"); tz=tz);
julia> display(ct);
```
""" conflict_timeline

@doc raw"""
    filter_events(df::DataFrame; tz::TimeZone, text="", weekdays=1:7, hours=0:23)

Filter events by text and time windows.

**Examples**

```julia
julia> using TimeWeaver, TimeZones, DataFrames, Dates
julia> tz = tz"Europe/Istanbul";
julia> df = DataFrame(uid=["a","b"],
                      summary=["Standup","Gym"],
                      dtstart=[ZonedDateTime(2025,9,1,9,0,0,tz),
                               ZonedDateTime(2025,9,1,19,0,0,tz)],
                      dtend=[ZonedDateTime(2025,9,1,9,30,0,tz),
                             ZonedDateTime(2025,9,1,20,0,0,tz)]);
julia> g = filter_events(df; tz=tz, text="gym", weekdays=[1], hours=19:21);
julia> nrow(g)
1
```

```julia
julia> filter_events(df; tz=tz, text="focus") |> nrow
0
```
""" filter_events

@doc raw"""
    utilization(df::DataFrame; tz::TimeZone) -> Float64

Return fraction of busy minutes within the covered period (0–1).

**Examples**

```julia
julia> using TimeWeaver, TimeZones
julia> u = utilization(load_ics("data/mycalendar.ics"); tz=tz"Europe/Istanbul");
julia> 0.0 ≤ u ≤ 1.0
true
```

```julia
julia> isa(u, Real)
true
```
""" utilization

@doc raw"""
    simulate_event(df::DataFrame, start::ZonedDateTime, stop::ZonedDateTime; summary="WhatIf")

Report whether a hypothetical event would conflict, and which events would be impacted.

**Examples**

```julia
julia> using TimeWeaver, TimeZones, Dates, DataFrames
julia> tz = tz"Europe/Istanbul";
julia> df = DataFrame(uid=["a"], summary=["A"],
                      dtstart=[ZonedDateTime(2025,9,2,10,0,0,tz)],
                      dtend=[ZonedDateTime(2025,9,2,11,0,0,tz)]);
julia> res = simulate_event(df, ZonedDateTime(2025,9,2,10,30,0,tz),
                               ZonedDateTime(2025,9,2,10,45,0,tz));
julia> res.would_conflict
true
```

```julia
julia> names(res.impacted) |> x->all(in.(["uid","summary","overlap_start","overlap_end"], Ref(x)))
true
```
""" simulate_event
