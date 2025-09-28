# == Plots ==
using Dates
using DataFrames
using TimeZones
using Plots

"""
    heatmap_hours(df::DataFrame; tz::TimeZone=tz"UTC",
                  title::AbstractString="eekly Occupancy Heatmap?")

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
    plot_timeline(df; tz=tz"UTC")

Gantt-benzeri zaman çizelgesi. X ekseni, df içindeki etkinliklerin
ilk başlangic son bitiş zamanina otomatik zoom yapar.
"""
function plot_timeline(df::DataFrame; tz::TimeZone=tz"UTC")
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)

    if nrow(d) == 0
        return plot(title="No events")
    end

    d = sort(d, :dtstart)
    d[!, :row] = 1:nrow(d)

    # X sınırları: tam otomatik (çok küçük tampon)
    tmin = minimum(d.dtstart)
    tmax = maximum(d.dtend)
    xlo  = DateTime(tmin) # + Minute(0)
    xhi  = DateTime(tmax) # + Minute(0)

    cols = fill(:steelblue, nrow(d))
    plt = plot(; legend=false, xlabel="Time ($(tz))", ylabel="Event index", xlims=(xlo, xhi))
    for r in eachrow(d)
        plot!([DateTime(r.dtstart), DateTime(r.dtend)], [r.row, r.row]; lw=8, color=cols[r.row])
    end
    yticks!(1:nrow(d), string.(coalesce.(d.summary, d.uid)))
    return plt
end




"""
    plot_conflicts(df; tz=tz"UTC")

Çakışan etkinlikleri kırmızı gösteren zaman çizelgesi.
X ekseni, yalnızca çatışmaya karışan etkinliklerin min–max aralığına (otomatik)
zoom yapar; çatışma yoksa tüm etkinliklerin aralığını kullanır.
"""
function plot_conflicts(df::DataFrame; tz::TimeZone=tz"UTC")
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)

    if nrow(d) == 0
        return plot(title="No events")
    end

    # Çakışan UID’leri bul
    conf = conflicts(d)
    has_conf = Dict(u => false for u in d.uid)
    for r in eachrow(conf)
        has_conf[r.uid1] = true
        has_conf[r.uid2] = true
    end

    d = sort(d, :dtstart)
    d[!, :row] = 1:nrow(d)

    """
    # X sınırları: önce sadece çatışanlar, yoksa hepsi
    if any(values(has_conf))
        df_conf = filter(r -> get(has_conf, r.uid, false), d)
        tmin = minimum(df_conf.dtstart);  tmax = maximum(df_conf.dtend)
    else
        tmin = minimum(d.dtstart);        tmax = maximum(d.dtend)
    end
    """
    tmin = minimum(d.dtstart)
    tmax = maximum(d.dtend)
    xlo  = DateTime(tmin) # + Minute(0)
    xhi  = DateTime(tmax) # + Minute(0)
    xlo = DateTime(tmin);  xhi = DateTime(tmax)

    plt = plot(; legend=false, xlabel="Time ($(tz))", ylabel="Event index", xlims=(xlo, xhi))
    for r in eachrow(d)
        color = get(has_conf, r.uid, false) ? :red : :gray
        plot!([DateTime(r.dtstart), DateTime(r.dtend)], [r.row, r.row]; lw=8, color=color)
    end
    yticks!(1:nrow(d), string.(coalesce.(d.summary, d.uid)))
    return plt
end







"""
    conflict_timeline(df; tz=tz"UTC", show_nonconflicts::Bool=false)

Only events that participate in at least one conflict are drawn as horizontal bars.
X axis auto-zooms to the min–max of the conflicting events.
If `show_nonconflicts=true`, non-conflicting events are drawn in light gray for context.
"""
function conflict_timeline(df::DataFrame; tz::TimeZone=tz"UTC", show_nonconflicts::Bool=false)
    # Mark conflicting UIDs
    conf = conflicts(df)
    conf_uids = Set{eltype(df.uid)}()
    for r in eachrow(conf)
        push!(conf_uids, r.uid1); push!(conf_uids, r.uid2)
    end

    # Convert to plotting tz
    d = copy(df)
    d[!, :dtstart] = astimezone.(d.dtstart, tz)
    d[!, :dtend]   = astimezone.(d.dtend,   tz)

    # Auto zoom range
    if !isempty(conf_uids)
        dc = filter(r -> r.uid in conf_uids, d)
    else
        dc = d  # no conflicts: fall back to all
    end
    if nrow(dc) == 0
        return plot(title="No events")
    end

    tmin = minimum(dc.dtstart)
    tmax = maximum(dc.dtend)
    xlo  = DateTime(tmin)
    xhi  = DateTime(tmax)

    # Build the plot
    d = sort(d, :dtstart)
    d[!, :row] = 1:nrow(d)
    plt = plot(; legend=false, xlabel="Time ($(tz))", ylabel="Event",
               xlims=(xlo, xhi), size=(1200, 720),
               tickfont=font(10), guidefont=font(12))

    # Optional context: non-conflicts in light gray
    if show_nonconflicts
        for r in eachrow(d)
            if !(r.uid in conf_uids)
                plot!([DateTime(r.dtstart), DateTime(r.dtend)], [r.row, r.row];
                      lw=6, color=:lightgray, alpha=0.6)
            end
        end
    end

    # Conflicting events in red
    for r in eachrow(d)
        if r.uid in conf_uids
            plot!([DateTime(r.dtstart), DateTime(r.dtend)], [r.row, r.row];
                  lw=8, color=:red)
        end
    end

    yticks!(1:nrow(d), string.(coalesce.(d.summary, d.uid)))
    return plt
end
