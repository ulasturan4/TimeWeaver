# src/schedule.jl
# == Calendar filtering, utilization stats, availability intersection, and suggestions ==

using Dates
using DataFrames
using Statistics
using TimeZones

# ------------------------------------------------------------------------
# filter_events
# ------------------------------------------------------------------------

"""
    filter_events(df::DataFrame;
                  tz::TimeZone = tz"UTC",
                  range::Union{Nothing,Tuple{ZonedDateTime,ZonedDateTime}} = nothing,
                  categories::Union{Nothing,AbstractVector} = nothing,
                  text::Union{Nothing,AbstractString} = nothing,
                  weekdays::Union{Nothing,AbstractVector{Int}} = nothing,
                  hours::Union{Nothing,AbstractVector{Int}} = nothing) -> DataFrame

Filter events by multiple criteria.

# Arguments
- `df::DataFrame`: A calendar table with at least the columns
  `:uid`, `:summary`, `:dtstart::ZonedDateTime`, `:dtend::ZonedDateTime`,
  and optionally `:category`.

# Keyword Arguments
- `tz`: Target timezone used for evaluating weekday/hour and range
  intersections. Events are converted via `astimezone` before filtering.
- `range`: Optional time window `(start, stop)`; keeps events that
  intersect the window (`dtend > start && dtstart < stop`).
- `categories`: Keep events whose `:category` is in this list (if present).
- `text`: Case-insensitive substring to match in `:summary`.
- `weekdays`: Keep events whose start day-of-week is in this set (1=Mon, …, 7=Sun).
- `hours`: Keep events whose start hour is in this set (0–23).

# Returns
A filtered `DataFrame` preserving the input schema.

# Examples
```julia
julia> d = filter_events(df; tz=tz"Europe/Istanbul", weekdays=[1,2,3], hours=9:17);

julia> s = ZonedDateTime(2025,8,1,0,0,0,tz"Europe/Istanbul");
julia> e = s + Day(7);
julia> d2 = filter_events(df; tz=tz"Europe/Istanbul", text="standup", range=(s,e));
```
"""
function filter_events(df::DataFrame;
                       tz::TimeZone = tz"UTC",
                       range::Union{Nothing,Tuple{ZonedDateTime,ZonedDateTime}} = nothing,
                       categories::Union{Nothing,AbstractVector} = nothing,
                       text::Union{Nothing,AbstractString} = nothing,
                       weekdays::Union{Nothing,AbstractVector{Int}} = nothing,
                       hours::Union{Nothing,AbstractVector{Int}} = nothing)
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)

    if range !== nothing
        s, e = range
        d = filter(r -> r.dtend > s && r.dtstart < e, d)  # intersect window
    end
    if categories !== nothing && :category ∈ names(d)
        S = Set(string.(categories))
        d = filter(r -> !ismissing(r.category) && string(r.category) in S, d)
    end
    if text !== nothing
        pat = lowercase(String(text))
        d = filter(r -> occursin(pat, lowercase(string(coalesce(r.summary, "")))), d)
    end
    if weekdays !== nothing
        W = Set(weekdays)
        d = filter(r -> dayofweek(r.dtstart) in W, d)
    end
    if hours !== nothing
        H = Set(hours)
        d = filter(r -> hour(r.dtstart) in H, d)
    end
    return d
end


# ------------------------------------------------------------------------
# utilization
# ------------------------------------------------------------------------

"""
    utilization(df::DataFrame; tz::TimeZone = tz"UTC", by::Union{Symbol,Period} = :day) -> DataFrame

Aggregate calendar utilization by bucket and compute descriptive statistics.

If `by` is a `Symbol`, it must be one of:
- `:day`   — aggregates by calendar day (local to `tz`)
- `:week`  — aggregates by week (Monday as week start)
- `:month` — aggregates by calendar month

If `by` is a `Period` (e.g. `Day(3)`, `Week(2)`), events are binned into
fixed-size windows starting at the minimum event start.

# Arguments
- `df::DataFrame`: Calendar table with `:dtstart`, `:dtend`.

# Keyword Arguments
- `tz`: Target timezone used for bucketing.
- `by`: Symbol or Period controlling the aggregation buckets.

# Returns
A `DataFrame` with columns:
- `:bucket` (Date/DateTime bucket anchor),
- `:busy_minutes` (sum of event durations in minutes),
- `:events` (count of events),
- `:mean_duration`, `:median_duration`, `:std_duration` (minutes).

# Examples
```julia
julia> util_d = utilization(df; tz=tz"Europe/Istanbul", by=:day);

julia> util_w = utilization(df; tz=tz"Europe/Istanbul", by=:week);

julia> util_m = utilization(df; tz=tz"Europe/Istanbul", by=:month);

julia> util_3d = utilization(df; tz=tz"Europe/Istanbul", by=Day(3));
```
"""
function utilization(df::DataFrame; tz::TimeZone = tz"UTC", by::Union{Symbol,Period} = :day)
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)
    d[!, :duration_min] = round.(Int, (d.dtend .- d.dtstart) ./ Minute(1))

if by isa Symbol
    bucket = if by === :day
        # Calendar day in target timezone
        Date.(d.dtstart)
    elseif by === :week
        # Week anchor = Monday of that week (ISO-style)
        Date.(d.dtstart) .- Day.(dayofweek.(d.dtstart) .- 1)
    elseif by === :month
        # First day of month (FIX: use Date/Int, not Year/Month wrappers)
        firstdayofmonth.(Date.(d.dtstart))
        # (Alternatively: Date.(year.(d.dtstart), month.(d.dtstart), 1))
    else
        error("by must be :day, :week or :month when Symbol")
    end
    d[!, :bucket] = bucket
else
    # Custom fixed-size windows (e.g., Day(3), Week(2))
    t0 = DateTime(minimum(d.dtstart))
    t1 = DateTime(maximum(d.dtend))
    edges = DateTime[]
    t = t0
    while t <= t1
        push!(edges, t)
        t += by
    end
    push!(edges, t1 + Millisecond(1))

    @inline function _bucket_of(x::DateTime)
        idx = searchsortedlast(edges, x)
        return edges[idx]
    end
    d[!, :bucket] = [_bucket_of(DateTime(x)) for x in d.dtstart]
end

g = groupby(d, :bucket)
return combine(g,
    :duration_min => sum     => :busy_minutes,
    nrow                      => :events,
    :duration_min => mean    => :mean_duration,
    :duration_min => median  => :median_duration,
    :duration_min => std     => :std_duration,
)
end

