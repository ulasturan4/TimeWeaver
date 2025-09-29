# == ICS I/O and normalization (robust parser, Apple Calendar–friendly) ==

# Helpers ----------------------------------------------------------------------

"""
    _unfold(s::AbstractString) -> Vector{String}

Unfold RFC 5545 (iCalendar) **folded lines** by concatenating any line that starts
with a single space or tab to the previous line, after stripping the leading whitespace.

# Arguments
- `s::AbstractString`: Raw iCalendar text (may contain `\\r\\n` or `\\n` line breaks).

# Returns
- `Vector{String}`: Unfolded lines, one entry per logical line.

# Examples
julia> txt = "SUMMARY:Very long\\n continuation\\nDESCRIPTION:Hello\\n\\tWorld"
julia> _unfold(txt)
2-element Vector{String}:
 "SUMMARY:Very longcontinuation"
 "DESCRIPTION:HelloWorld"

julia> _unfold("KEY:val\\n NEXT:line")
2-element Vector{String}:
 "KEY:val"
 "NEXT:line"
"""
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

"""
    _split_prop(ln::AbstractString) -> Tuple{String, Dict{String,String}, String}

Split an iCalendar/RFC 5545 property line of the form
`NAME;PARAM=VAL;PARAM2=VAL2:VALUE` into `(name, params, value)`.

- `name` — property name as `String`
- `params` — dictionary of parameter key–value pairs (bare parameters are ignored)
- `value` — the text after the first `:` (empty string if `:` is absent)

# Arguments
- `ln::AbstractString`: A single unfolded property line.

# Returns
- `Tuple{String, Dict{String,String}, String}`: `(name, params, value)`.

# Examples
julia> _split_prop("ATTENDEE;CN=Alice;ROLE=REQ-PARTICIPANT:mailto:alice@example.com")
("ATTENDEE", Dict("CN" => "Alice", "ROLE" => "REQ-PARTICIPANT"), "mailto:alice@example.com")

julia> _split_prop("SUMMARY:Team Sync")
("SUMMARY", Dict{String,String}(), "Team Sync")

julia> _split_prop("UID;X-CUSTOM=abc123")
("UID", Dict("X-CUSTOM" => "abc123"), "")
"""
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

"""
    _unescape_ics_text(s::AbstractString) -> String

De-escape RFC 5545 (iCalendar) text by converting common escape sequences:
- `\\n` / `\\N` → newline
- `\\,` → comma `,`
- `\\;` → semicolon `;`
- `\\\\` → backslash `\`

# Arguments
- `s::AbstractString`: Raw ICS text (with RFC 5545 escapes).

# Returns
- `String`: The unescaped text.

# Examples
julia> _unescape_ics_text("Line1\\nLine2")
"Line1\nLine2"

julia> _unescape_ics_text("Alice\\, Bob; note\\; ok \\\\ path")
"Alice, Bob; note; ok \\ path"
"""
# De-escape ICS text: \n, \, \; \, \\
function _unescape_ics_text(s::AbstractString)
    s = replace(s, "\\n" => "\n", "\\N" => "\n")
    s = replace(s, "\\," => ",")
    s = replace(s, "\\;" => ";")
    s = replace(s, "\\\\" => "\\")
    return s
end



"""
    _parse_dt(value::AbstractString; tzid::Union{Nothing,AbstractString}=nothing) -> ZonedDateTime

Parse ISO-8601 **basic** datetime forms used in iCalendar (RFC 5545) and return a
`ZonedDateTime`. Supports UTC forms with a trailing `Z`, and local forms (with or
without time) optionally interpreted under `tzid`.

Accepted formats:
- UTC (`...Z`): `yyyymmddTHHMMSSZ`, `yyyymmddTHHMMZ`, `yyyymmddZ`  → parsed in `UTC`
- Local: `yyyymmddTHHMMSS`, `yyyymmddTHHMM`, `yyyymmdd`
  - Interpreted in `tzid` if provided, else `UTC`.

# Arguments
- `value::AbstractString`: ISO-8601 basic string from ICS (e.g., `"20250812T140000Z"`).
- `tzid::Union{Nothing,AbstractString}`: IANA timezone name for local values
  (e.g., `"Europe/Istanbul"`). Ignored for `...Z`. Default: `nothing` → `UTC`.

# Returns
- `ZonedDateTime`: Parsed timestamp with timezone.

# Examples
julia> _parse_dt("20250812T140000Z")
2025-08-12T14:00:00+00:00

julia> _parse_dt("20250812T1400"; tzid="Europe/Istanbul")
2025-08-12T14:00:00+03:00
"""
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


"""
    _parse_duration(s::AbstractString) -> Dates.CompoundPeriod

Parse an ISO-8601 **DURATION** string (RFC 5545/ICS), such as `P1D`, `PT1H30M`,
`PT45M`, or `PT30S`, and return the corresponding `Dates.CompoundPeriod`
(e.g., `Day(1) + Hour(1) + Minute(30)`).

Accepted forms:
- `P<d>D` (days)
- `PT<h>H<m>M<s>S` (any subset of hours, minutes, seconds)
- Combination: `P<d>D` with optional `T…` time part

# Arguments
- `s::AbstractString`: Duration in ISO-8601 basic format (e.g., `"PT1H30M"`).

# Returns
- `Dates.CompoundPeriod`: Sum of `Day`, `Hour`, `Minute`, `Second`.

# Examples
julia> _parse_duration("P1D")
1 day

julia> _parse_duration("PT1H30M")
1 hour, 30 minutes

julia> _parse_duration("PT45M")
45 minutes

julia> _parse_duration("PT30S")
30 seconds
"""
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
