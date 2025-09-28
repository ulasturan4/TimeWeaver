# == What-if simulator ==

"""
    simulate_event(df::DataFrame, start::ZonedDateTime, stop::ZonedDateTime; summary::AbstractString="WhatIf")
        -> NamedTuple{(:would_conflict, :impacted), Tuple{Bool,DataFrame}}

Check whether inserting a hypothetical event [start, stop) would cause conflicts.
Also return the subset of events it overlaps with.
"""
function simulate_event(df::DataFrame, start::ZonedDateTime, stop::ZonedDateTime; summary::AbstractString="WhatIf")
    rows = NamedTuple[]
    for r in eachrow(df)
        os = max(r.dtstart, start)
        oe = min(r.dtend, stop)
        if os < oe
            push!(rows, (uid=r.uid, summary=r.summary, overlap_start=os, overlap_end=oe))
        end
    end
    impacted = DataFrame(rows)
    return (would_conflict = nrow(impacted) > 0, impacted = impacted)
end
