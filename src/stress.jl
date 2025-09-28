# == Occupancy & stress scoring ==

"""
    occupancy_table(df::DataFrame; by::Symbol=:day, tz::TimeZone=tz"UTC") -> DataFrame

Compute occupied minutes per day or per (weekday,hour) bucket.
- by=:day → columns: :date, :busy_minutes
- by=:hour → columns: :weekday (1=Mon), :hour, :busy_minutes
"""
function occupancy_table(df::DataFrame; by::Symbol=:day, tz::TimeZone=tz"UTC")
    # Convert to target tz for bucketing
    loc = similar(df.dtstart, ZonedDateTime)
    loe = similar(df.dtend,   ZonedDateTime)
    for i in 1:nrow(df)
        loc[i] = astimezone(df[i, :dtstart], tz)
        loe[i] = astimezone(df[i, :dtend], tz)
    end

    # Build minute sets per bucket
    buckets = Dict{Any, Set{DateTime}}()
    for i in 1:nrow(df)
        s = DateTime(loc[i])
        e = DateTime(loe[i])
        t = s
        while t < e
            key = by === :day  ? Date(t) :
                  by === :hour ? (dayofweek(t), hour(t)) :
                  error("by must be :day or :hour")
            if !haskey(buckets, key); buckets[key] = Set{DateTime}(); end
            push!(buckets[key], t)
            t += Minute(1)
        end
    end

    if by === :day
        return DataFrame([(date=k, busy_minutes=length(v)) for (k,v) in buckets])
    else
        return DataFrame([(weekday=k[1], hour=k[2], busy_minutes=length(v)) for (k,v) in buckets])
    end
end

"""
    stress_index(df::DataFrame; by::Symbol=:day, tz::TimeZone=tz"UTC") -> DataFrame

Map busy_minutes to a 0–100 "stress score" per bucket using a saturating function.
"""
function stress_index(df::DataFrame; by::Symbol=:day, tz::TimeZone=tz"UTC")
    occ = occupancy_table(df; by=by, tz=tz)
    occ[!, :stress] = @. 100 * (1 - exp(-occ.busy_minutes/240))
    return occ
end
