// dateutil `parser.isoparser`: a strict(er) ISO-8601 parser.
//
// Python works on the ASCII-encoded bytes of the input; after the ASCII
// check every code unit here is one byte, so String indices match.

///|
/// dateutil `isoparser`.
pub struct IsoParser {
  priv sep : Char?
}

///|
/// `isoparser(sep=None)`: `sep` is the single character separating the
/// date and time portions; `None` accepts any single character. For strict
/// ISO-8601 adherence pass `"T"`.
///
/// Raises `ValueError` unless `sep` is a single, non-numeric ASCII
/// character.
pub fn IsoParser::new(sep? : String) -> IsoParser raise @datetime.DateTimeError {
  match sep {
    None => { sep: None, }
    Some(s) => {
      let chars = s.to_array()
      if chars.length() != 1 ||
        chars[0].to_int() >= 128 ||
        chars[0] is ('0'..='9') {
        raise @datetime.ValueError(
          "Separator must be a single, non-numeric ASCII character",
        )
      }
      { sep: Some(chars[0]), }
    }
  }
}

///|
/// The `_takes_ascii` check.
fn check_ascii(s : String) -> Unit raise @datetime.DateTimeError {
  for c in s {
    if c.to_int() >= 128 {
      raise @datetime.ValueError(
        "ISO-8601 strings should contain only ASCII characters",
      )
    }
  }
}

///|
/// Python `s[a:b]` on the ASCII bytes (clamped).
fn bslice(s : String, a : Int, b : Int) -> String {
  let n = s.length()
  let a = if a > n { n } else { a }
  let b = if b > n { n } else { b }
  if a >= b {
    ""
  } else {
    s.unsafe_substring(start=a, end=b)
  }
}

///|
/// Python `repr(bytes)` for ASCII data.
fn bytes_repr(s : String) -> String {
  let quote = if s.contains("'") && !s.contains("\"") { '"' } else { '\'' }
  let sb = StringBuilder()
  sb.write_string("b")
  sb.write_char(quote)
  for c in s {
    match c {
      '\\' => sb.write_string("\\\\")
      '\t' => sb.write_string("\\t")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      _ =>
        if c == quote {
          sb.write_char('\\')
          sb.write_char(c)
        } else if c.to_int() < 32 || c.to_int() >= 127 {
          let h = "0123456789abcdef"
          sb.write_string("\\x")
          sb.write_char(h.get_char(c.to_int() / 16).unwrap())
          sb.write_char(h.get_char(c.to_int() % 16).unwrap())
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char(quote)
  sb.to_string()
}

///|
/// Python `int(b)` for ASCII bytes: optional ASCII whitespace, sign, and
/// digits with single `_` separators.
fn bytes_int(s : String) -> Int raise @datetime.DateTimeError {
  let chars = s.to_array()
  let mut a = 0
  let mut b = chars.length()
  let ws = (c : Char) => c is (' ' | '\t' | '\n' | '\r' | '\u{b}' | '\u{c}')
  while a < b && ws(chars[a]) {
    a += 1
  }
  while b > a && ws(chars[b - 1]) {
    b -= 1
  }
  let mut neg = false
  if a < b && chars[a] is ('+' | '-') {
    neg = chars[a] == '-'
    a += 1
  }
  match digits_value(chars[a:b], true) {
    Some(v) => {
      let v = if neg { -v } else { v }
      if v > 2147483647L || v < -2147483648L {
        raise @datetime.OverflowError(
          "Python int too large to convert to C int",
        )
      }
      v.to_int()
    }
    None =>
      raise @datetime.ValueError(
        "invalid literal for int() with base 10: \{bytes_repr(s)}",
      )
  }
}

///|
/// `isoparser._parse_isodate_common`
fn parse_isodate_common(
  dt_str : String,
) -> (Array[Int], Int) raise @datetime.DateTimeError {
  let len_str = dt_str.length()
  let components = [1, 1, 1]
  if len_str < 4 {
    raise @datetime.ValueError("ISO string too short")
  }
  // Year
  components[0] = bytes_int(bslice(dt_str, 0, 4))
  let mut pos = 4
  if pos >= len_str {
    return (components, pos)
  }
  let has_sep = bslice(dt_str, pos, pos + 1) == "-"
  if has_sep {
    pos += 1
  }
  // Month
  if len_str - pos < 2 {
    raise @datetime.ValueError("Invalid common month")
  }
  components[1] = bytes_int(bslice(dt_str, pos, pos + 2))
  pos += 2
  if pos >= len_str {
    if has_sep {
      return (components, pos)
    } else {
      raise @datetime.ValueError("Invalid ISO format")
    }
  }
  if has_sep {
    if bslice(dt_str, pos, pos + 1) != "-" {
      raise @datetime.ValueError("Invalid separator in ISO string")
    }
    pos += 1
  }
  // Day
  if len_str - pos < 2 {
    raise @datetime.ValueError("Invalid common day")
  }
  components[2] = bytes_int(bslice(dt_str, pos, pos + 2))
  (components, pos + 2)
}

///|
/// `isoparser._calculate_weekdate`: the inverse of `date.isocalendar`.
fn calculate_weekdate(
  year : Int,
  week : Int,
  day : Int,
) -> @datetime.Date raise @datetime.DateTimeError {
  if !(0 < week && week < 54) {
    raise @datetime.ValueError("Invalid week: \{week}")
  }
  if !(0 < day && day < 8) {
    // Range is 1-7
    raise @datetime.ValueError("Invalid weekday: \{day}")
  }
  // Get week 1 for the specific year:
  let jan_4 = @datetime.Date::new(year, 1, 4) // Week 1 always has January 4th in it
  let week_1 = jan_4.sub(
    @datetime.TimeDelta::new(days=jan_4.isocalendar().2 - 1),
  )
  // Now add the specific number of weeks and days to get what we want
  let week_offset = (week - 1) * 7 + (day - 1)
  week_1.add(@datetime.TimeDelta::new(days=week_offset))
}

///|
/// `isoparser._parse_isodate_uncommon`
fn parse_isodate_uncommon(
  dt_str : String,
) -> (Array[Int], Int) raise @datetime.DateTimeError {
  if dt_str.length() < 4 {
    raise @datetime.ValueError("ISO string too short")
  }
  // All ISO formats start with the year
  let year = bytes_int(bslice(dt_str, 0, 4))
  let has_sep = bslice(dt_str, 4, 5) == "-"
  let mut pos = 4 + (if has_sep { 1 } else { 0 }) // Skip '-' if it's there
  let base_date = if bslice(dt_str, pos, pos + 1) == "W" {
    // YYYY-?Www-?D?
    pos += 1
    let weekno = bytes_int(bslice(dt_str, pos, pos + 2))
    pos += 2
    let mut dayno = 1
    if dt_str.length() > pos {
      if (bslice(dt_str, pos, pos + 1) == "-") != has_sep {
        raise @datetime.ValueError("Inconsistent use of dash separator")
      }
      pos += if has_sep { 1 } else { 0 }
      dayno = bytes_int(bslice(dt_str, pos, pos + 1))
      pos += 1
    }
    calculate_weekdate(year, weekno, dayno)
  } else {
    // YYYYDDD or YYYY-DDD
    if dt_str.length() - pos < 3 {
      raise @datetime.ValueError("Invalid ordinal day")
    }
    let ordinal_day = bytes_int(bslice(dt_str, pos, pos + 3))
    pos += 3
    let ndays = 365 + (if @datetime.is_leap(year) { 1 } else { 0 })
    if ordinal_day < 1 || ordinal_day > ndays {
      raise @datetime.ValueError(
        "Invalid ordinal day \{ordinal_day} for year \{year}",
      )
    }
    @datetime.Date::new(year, 1, 1).add(
      @datetime.TimeDelta::new(days=ordinal_day - 1),
    )
  }
  ([base_date.year, base_date.month, base_date.day], pos)
}

///|
/// `isoparser._parse_isodate`
fn parse_isodate_any(
  dt_str : String,
) -> (Array[Int], Int) raise @datetime.DateTimeError {
  parse_isodate_common(dt_str) catch {
    @datetime.ValueError(_) => parse_isodate_uncommon(dt_str)
    e => raise e
  }
}

///|
/// `isoparser._FRACTION_REGEX.match(s)`: `[.,]([0-9]+)` at the start;
/// returns (digits, matched length).
fn match_fraction(s : String) -> (String, Int)? {
  guard s.get_char(0) is Some('.' | ',') else { return None }
  let mut i = 1
  while i < s.length() && s.get_char(i) is Some('0'..='9') {
    i += 1
  }
  if i == 1 {
    None
  } else {
    Some((s.unsafe_substring(start=1, end=i), i))
  }
}

///|
/// The components of `_parse_isotime`: hour, minute, second, microsecond
/// and zone.
priv struct IsoTime {
  parts : Array[Int]
  mut tz : @datetime.Tz?
}

///|
/// `isoparser._parse_isotime`
fn parse_isotime_parts(
  timestr : String,
) -> IsoTime raise @datetime.DateTimeError {
  let len_str = timestr.length()
  let components = { parts: [0, 0, 0, 0], tz: None, }
  let mut pos = 0
  let mut comp = -1
  if len_str < 2 {
    raise @datetime.ValueError("ISO time too short")
  }
  let mut has_sep = false
  while pos < len_str && comp < 5 {
    comp += 1
    if bslice(timestr, pos, pos + 1) is ("-" | "+" | "Z" | "z") {
      // Detect time zone boundary
      components.tz = Some(
        parse_tzstr_impl(bslice(timestr, pos, len_str), true),
      )
      pos = len_str
      break
    }
    if comp == 1 && bslice(timestr, pos, pos + 1) == ":" {
      has_sep = true
      pos += 1
    } else if comp == 2 && has_sep {
      if bslice(timestr, pos, pos + 1) != ":" {
        raise @datetime.ValueError("Inconsistent use of colon separator")
      }
      pos += 1
    }
    if comp < 3 {
      // Hour, minute, second
      components.parts[comp] = bytes_int(bslice(timestr, pos, pos + 2))
      pos += 2
    }
    if comp == 3 {
      // Fraction of a second
      guard match_fraction(bslice(timestr, pos, len_str)) is Some((digits, n)) else {
        continue
      }
      let us_str = bslice(digits, 0, 6) // Truncate to microseconds
      let mut scale = 1
      for _ in 0..<(6 - us_str.length()) {
        scale *= 10
      }
      components.parts[comp] = bytes_int(us_str) * scale
      pos += n
    }
  }
  if pos < len_str {
    raise @datetime.ValueError("Unused components in ISO string")
  }
  if components.parts[0] == 24 {
    // Standard supports 00:00 and 24:00 as representations of midnight
    if components.parts[1] != 0 ||
      components.parts[2] != 0 ||
      components.parts[3] != 0 {
      raise @datetime.ValueError("Hour may only be 24 at 24:00:00.000")
    }
  }
  components
}

///|
/// `isoparser._parse_tzstr`
fn parse_tzstr_impl(
  tzstr : String,
  zero_as_utc : Bool,
) -> @datetime.Tz raise @datetime.DateTimeError {
  if tzstr == "Z" || tzstr == "z" {
    return @tz.utc
  }
  let n = tzstr.length()
  if !(n == 3 || n == 5 || n == 6) {
    raise @datetime.ValueError(
      "Time zone offset must be 1, 3, 5 or 6 characters",
    )
  }
  let mult = match bslice(tzstr, 0, 1) {
    "-" => -1
    "+" => 1
    _ => raise @datetime.ValueError("Time zone offset requires sign")
  }
  let hours = bytes_int(bslice(tzstr, 1, 3))
  let minutes = if n == 3 {
    0
  } else {
    let start = if bslice(tzstr, 3, 4) == ":" { 4 } else { 3 }
    bytes_int(bslice(tzstr, start, n))
  }
  if zero_as_utc && hours == 0 && minutes == 0 {
    @tz.utc
  } else {
    if minutes > 59 {
      raise @datetime.ValueError("Invalid minutes in time zone offset")
    }
    if hours > 23 {
      raise @datetime.ValueError("Invalid hours in time zone offset")
    }
    @tz.tzoffset(None, mult * (hours * 60 + minutes) * 60)
  }
}

///|
/// `isoparser.isoparse(dt_str)`: parse an ISO-8601 datetime string.
///
/// Date formats: `YYYY`, `YYYY-MM`, `YYYY-MM-DD` / `YYYYMMDD`, ISO weeks
/// `YYYY-Www[-D]` / `YYYYWww[D]` and ordinal days `YYYY-DDD` / `YYYYDDD`.
/// Time formats (after one separator character): `hh`, `hh:mm` / `hhmm`,
/// `hh:mm:ss` / `hhmmss`, with an optional `.`/`,` fraction (extra digits
/// beyond microseconds are truncated) and an optional `Z`, `±HH:MM`,
/// `±HHMM` or `±HH` offset. `24:00` is midnight of the following day.
///
/// Raises `ValueError` (`@datetime.DateTimeError`) for invalid strings.
pub fn IsoParser::isoparse(
  self : IsoParser,
  dt_str : String,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  check_ascii(dt_str)
  let (components, pos) = parse_isodate_any(dt_str)
  let mut time : IsoTime? = None
  if dt_str.length() > pos {
    let sep_ok = match self.sep {
      None => true
      Some(c) => bslice(dt_str, pos, pos + 1) == c.to_string()
    }
    if sep_ok {
      time = Some(parse_isotime_parts(bslice(dt_str, pos + 1, dt_str.length())))
    } else {
      raise @datetime.ValueError("String contains unknown ISO components")
    }
  }
  match time {
    None => @datetime.DateTime::new(components[0], components[1], components[2])
    Some(t) => {
      let midnight24 = t.parts[0] == 24
      let hour = if midnight24 { 0 } else { t.parts[0] }
      let dt = @datetime.DateTime::new(
        components[0],
        components[1],
        components[2],
        hour~,
        minute=t.parts[1],
        second=t.parts[2],
        microsecond=t.parts[3],
        tzinfo?=t.tz,
      )
      if midnight24 {
        dt.add(@datetime.TimeDelta::new(days=1))
      } else {
        dt
      }
    }
  }
}

///|
/// `isoparser.parse_isodate(datestr)`: the date portion of an ISO string.
pub fn IsoParser::parse_isodate(
  self : IsoParser,
  datestr : String,
) -> @datetime.Date raise @datetime.DateTimeError {
  ignore(self)
  check_ascii(datestr)
  let (components, pos) = parse_isodate_any(datestr)
  if pos < datestr.length() {
    raise @datetime.ValueError(
      "String contains unknown ISO components: \{@datetime.py_str_repr(datestr)}",
    )
  }
  @datetime.Date::new(components[0], components[1], components[2])
}

///|
/// `isoparser.parse_isotime(timestr)`: the time portion of an ISO string.
pub fn IsoParser::parse_isotime(
  self : IsoParser,
  timestr : String,
) -> @datetime.Time raise @datetime.DateTimeError {
  ignore(self)
  check_ascii(timestr)
  let t = parse_isotime_parts(timestr)
  @datetime.Time::new(
    hour=if t.parts[0] == 24 { 0 } else { t.parts[0] },
    minute=t.parts[1],
    second=t.parts[2],
    microsecond=t.parts[3],
    tzinfo?=t.tz,
  )
}

///|
/// `isoparser.parse_tzstr(tzstr, zero_as_utc=True)`: an ISO offset (`Z`,
/// `±HH:MM`, `±HHMM`, `±HH`) as `tzutc` (for `Z` and, if `zero_as_utc`,
/// zero offsets) or `tzoffset`.
pub fn IsoParser::parse_tzstr(
  self : IsoParser,
  tzstr : String,
  zero_as_utc? : Bool = true,
) -> @datetime.Tz raise @datetime.DateTimeError {
  ignore(self)
  check_ascii(tzstr)
  parse_tzstr_impl(tzstr, zero_as_utc)
}

///|
/// dateutil's `DEFAULT_ISOPARSER`.
let default_isoparser : IsoParser = { sep: None, }

///|
/// dateutil `parser.isoparse(dt_str)` (the default `isoparser`'s method).
///
/// ```mbt check
/// test {
///   inspect(
///     @parser.isoparse("2014-02-04T12:30:15.224+05:00").repr(),
///     content="datetime.datetime(2014, 2, 4, 12, 30, 15, 224000, tzinfo=tzoffset(None, 18000))",
///   )
///   inspect(@parser.isoparse("2004-W53-7"), content="2005-01-02 00:00:00")
///   inspect(@parser.isoparse("2014-04-10T24:00"), content="2014-04-11 00:00:00")
/// }
/// ```
pub fn isoparse(
  dt_str : String,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  default_isoparser.isoparse(dt_str)
}
