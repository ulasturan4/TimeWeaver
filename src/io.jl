# == ICS I/O and normalization (robust parser, Apple Calendar–friendly) ==

# Helpers ----------------------------------------------------------------------

# Unfold RFC5545 folded lines
function _unfold(s::AbstractString)
    out = String[]
    for ln in split(s, r"\r?\n")
        if !isempty(out) && (startswith(ln, " ") || startswith(ln, "\t"))
            out[end] *= strip(ln)
        else
            push!(out, ln)
        end
    end
    return out
end

# Split "NAME;PARAM=VAL;PARAM2=VAL2:VALUE" → (name::String, Dict{String,String}, value::String)
function _split_prop(ln::AbstractString)
    name_and_params, value = occursin(":", ln) ? split(ln, ":", limit=2) : (ln, "")
    parts = split(name_and_params, ";")
    name = String(parts[1])
    params = Dict{String,String}()
    for p in parts[2:end]
        if occursin("=", p)
            k, v = split(p, "=", limit=2)
            params[String(k)] = String(v)
        else
            # bare parameter (rare) — ignore
        end
    end
    return name, params, String(value)
end

# De-escape ICS text: \n, \, \; \, \\
function _unescape_ics_text(s::AbstractString)
    s = replace(s, "\\n" => "\n", "\\N" => "\n")
    s = replace(s, "\\," => ",")
    s = replace(s, "\\;" => ";")
    s = replace(s, "\\\\" => "\\")
    return s
end

# Parse ISO8601 basic datetime variants used in ICS
function _parse_dt(value::AbstractString; tzid::Union{Nothing,AbstractString}=nothing)
    if endswith(value, "Z")
        core = replace(value[1:end-1], "T" => "")
        fmt = length(core) == 14 ? dateformat"yyyymmddHHMMSS" :
              length(core) == 12 ? dateformat"yyyymmddHHMM"   :
              length(core) == 8  ? dateformat"yyyymmdd"       :
              error("Unsupported UTC datetime format: $value")
        dt = DateTime(core, fmt)
        return ZonedDateTime(dt, tz"UTC")
    else
        # Local time or date-only
        fmt = if length(value) == 15
            dateformat"yyyymmddTHHMMSS"
        elseif length(value) == 13
            dateformat"yyyymmddTHHMM"
        elseif length(value) == 8
            dateformat"yyyymmdd"
        else
            error("Unsupported local datetime format: $value")
        end
        dt = DateTime(value, fmt)
        tz = isnothing(tzid) ? tz"UTC" : TimeZone(String(tzid))
        return ZonedDateTime(dt, tz)
    end
end

# Parse ISO8601 DURATION like P1D, PT1H30M, PT45M, PT30S
function _parse_duration(s::AbstractString)
    m = match(r"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$", s)
    m === nothing && error("Unsupported DURATION: $s")
    d  = m.captures[1] === nothing ? 0 : parse(Int, m.captures[1])
    hh = m.captures[2] === nothing ? 0 : parse(Int, m.captures[2])
    mm = m.captures[3] === nothing ? 0 : parse(Int, m.captures[3])
    ss = m.captures[4] === nothing ? 0 : parse(Int, m.captures[4])
    return Day(d) + Hour(hh) + Minute(mm) + Second(ss)
end

# Public API -------------------------------------------------------------------

"""
    load_ics(path::AbstractString) -> DataFrame

Read a `.ics` file into a DataFrame with columns:
:uid, :summary, :dtstart::ZonedDateTime, :dtend::ZonedDateTime, :category::Union{String,Missing}

Supports:
- Folded lines
- `TZID` parameter (Apple Calendar)
- `VALUE=DATE` (all-day)
- `DURATION` when `DTEND` is missing
- Ignores unrelated properties (VALARM, X-APPLE-*, ATTENDEE, etc.)
"""
function load_ics(path::AbstractString)
    raw = read(path, String)
    lines = _unfold(raw)

    rows = NamedTuple[]
    in_event = false

    # current event fields
    uid = summary = category = location = nothing
    dtstart = dtend = nothing
    duration = nothing
    tzid_start = tzid_end = nothing
    value_date_start = false
    value_date_end = false

    for ln in lines
        if ln == "BEGIN:VEVENT"
            in_event = true
            uid = summary = category = location = nothing
            dtstart = dtend = nothing
            duration = nothing
            tzid_start = tzid_end = nothing
            value_date_start = value_date_end = false
            continue
        elseif ln == "END:VEVENT"
            if dtstart !== nothing && dtend === nothing
                # allow DURATION or default 1 hour
                if duration !== nothing
                    dtend = dtstart + duration
                else
                    dtend = dtstart + Hour(1)
                end
            end
            if dtstart !== nothing && dtend !== nothing
                push!(rows, (uid = uid === nothing ? missing : uid,
                             summary = summary === nothing ? missing : summary,
                             dtstart = dtstart, dtend = dtend,
                             category = category === nothing ? missing : category))
            end
            in_event = false
            continue
        end

        if !in_event
            continue
        end

        name, params, value = _split_prop(ln)

        if name == "UID"
            uid = _unescape_ics_text(value)
        elseif name == "SUMMARY"
            summary = _unescape_ics_text(value)
        elseif name == "CATEGORIES"
            category = _unescape_ics_text(value)
        elseif name == "LOCATION"
            location = _unescape_ics_text(value)
        elseif name == "DTSTART"
            tzid = get(params, "TZID", nothing)
            if get(params, "VALUE", nothing) == "DATE"
                value_date_start = true
            end
            dtstart = _parse_dt(value; tzid=tzid)
        elseif name == "DTEND"
            tzid = get(params, "TZID", nothing)
            if get(params, "VALUE", nothing) == "DATE"
                value_date_end = true
            end
            dtend = _parse_dt(value; tzid=tzid)
        elseif name == "DURATION"
            duration = _parse_duration(value)
        else
            # ignore other properties
        end
    end

    return DataFrame(rows)
end

"""
    normalize_timezone!(df::DataFrame, tz::TimeZone)

Convert :dtstart and :dtend to the given `tz` in-place.
"""
function normalize_timezone!(df::DataFrame, tz::TimeZone)
    df[!, :dtstart] = astimezone.(df[!, :dtstart], tz)
    df[!, :dtend]   = astimezone.(df[!, :dtend], tz)
    return df
end
