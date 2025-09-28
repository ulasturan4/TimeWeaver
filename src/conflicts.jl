# == Conflict and overload detection ==

"""
    conflicts(df::DataFrame) -> DataFrame

Return all overlapping event pairs as rows with columns:
:uid1, :uid2, :overlap_start, :overlap_end, :minutes
"""
function conflicts(df::DataFrame)
    n = nrow(df)
    rows = NamedTuple[]
    for i in 1:n-1, j in i+1:n
        s1, e1 = df[i, :dtstart], df[i, :dtend]
        s2, e2 = df[j, :dtstart], df[j, :dtend]
        os = max(s1, s2)
        oe = min(e1, e2)
        if os < oe
            mins = Int(round(Dates.value(oe - os) / (60*1_000_000_000)))
            push!(rows, (uid1=df[i, :uid], uid2=df[j, :uid],
                         overlap_start=os, overlap_end=oe, minutes=mins))
        end
    end
    return DataFrame(rows)
end
