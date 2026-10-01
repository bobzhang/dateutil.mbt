///|
/// Python's `datetime.timezone`: a fixed offset from UTC with an optional
/// name.
priv struct FixedTimezone {
  offset : TimeDelta
  name : String?
  is_utc_singleton : Bool
}

///|
impl TzInfo for FixedTimezone with fn utcoffset(self, _) {
  Some(self.offset)
}

///|
impl TzInfo for FixedTimezone with fn dst(_, _) {
  None
}

///|
impl TzInfo for FixedTimezone with fn tzname(self, _) {
  match self.name {
    Some(n) => Some(n)
    None => Some(timezone_name_from_offset(self.offset))
  }
}

///|
impl TzInfo for FixedTimezone with fn fromutc(self, dt) {
  dt.add(self.offset)
}

///|
impl TzInfo for FixedTimezone with fn repr(self) {
  if self.is_utc_singleton {
    return "datetime.timezone.utc"
  }
  match self.name {
    None => "datetime.timezone(\{self.offset.repr()})"
    Some(n) => "datetime.timezone(\{self.offset.repr()}, \{py_str_repr(n)})"
  }
}

///|
impl TzInfo for FixedTimezone with fn eq_key(self) {
  Some("datetime.timezone:\{self.offset.repr()}")
}

///|
/// `UTC+HH:MM[:SS[.ffffff]]` as produced by `timezone._name_from_offset`.
fn timezone_name_from_offset(delta : TimeDelta) -> String {
  if delta.is_zero() {
    return "UTC"
  }
  let (sign, d) = if delta.days < 0 { ("-", -delta) } else { ("+", delta) }
  let hours = d.seconds / 3600
  let rest = d.seconds % 3600
  let minutes = rest / 60
  let seconds = rest % 60
  let micro = d.microseconds
  if micro != 0 {
    "UTC\{sign}\{pad(hours, 2)}:\{pad(minutes, 2)}:\{pad(seconds, 2)}.\{pad(micro, 6)}"
  } else if seconds != 0 {
    "UTC\{sign}\{pad(hours, 2)}:\{pad(minutes, 2)}:\{pad(seconds, 2)}"
  } else {
    "UTC\{sign}\{pad(hours, 2)}:\{pad(minutes, 2)}"
  }
}

///|
/// Python `repr()` of a string (single quotes unless the string contains
/// a single quote and no double quote).
pub fn py_str_repr(s : String) -> String {
  let quote = if s.contains("'") && !s.contains("\"") { '"' } else { '\'' }
  let buf = StringBuilder()
  buf.write_char(quote)
  for c in s {
    match c {
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c == quote {
          buf.write_char('\\')
          buf.write_char(c)
        } else if c.to_int() < 0x20 || c.to_int() == 0x7f {
          let h = c.to_int()
          buf.write_string("\\x")
          buf.write_string(hex_digit(h / 16))
          buf.write_string(hex_digit(h % 16))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char(quote)
  buf.to_string()
}

///|
fn hex_digit(n : Int) -> String {
  "0123456789abcdef".view(start_offset=n, end_offset=n + 1).to_owned()
}

///|
/// `datetime.timezone.utc`.
pub let utc : Tz = Tz::new(FixedTimezone::{
  offset: zero_timedelta,
  name: None,
  is_utc_singleton: true,
})

///|
/// `datetime.timezone(offset, name)`. The offset must be strictly between
/// -24h and +24h.
pub fn Tz::fixed(offset : TimeDelta, name? : String) -> Tz raise DateTimeError {
  if offset.days < -1 ||
    offset.days >= 1 ||
    (offset.days == -1 && offset.seconds == 0 && offset.microseconds == 0) {
    raise ValueError(
      "offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24), not \{offset.repr()}.",
    )
  }
  Tz::new(FixedTimezone::{ offset, name, is_utc_singleton: false, })
}
