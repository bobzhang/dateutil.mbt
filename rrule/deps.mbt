// Dependencies of `rrulestr` on `dateutil.parser` and `dateutil.tz`,
// isolated here.

///|
/// `parser.parse(s, ignoretz=ignoretz)` as used by `rrulestr` for DTSTART,
/// UNTIL, RDATE and EXDATE values.
///
/// TODO(parser): stopgap until the `parser` package lands; it accepts only
/// the RFC 5545 forms `YYYYMMDD[THHMM[SS]][Z]` (surrounding whitespace
/// ignored), while dateutil accepts anything `parser.parse` does.
fn parse_datetime(
  s : String,
  ignoretz : Bool,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  let s = py_strip(s)
  let n = s.length()
  fn bad() -> @datetime.DateTimeError {
    @datetime.ValueError("Unknown string format: " + s)
  }

  fn digits(start : Int, len : Int) -> Int raise @datetime.DateTimeError {
    let mut v = 0
    for i in start..<(start + len) {
      if i >= n || s[i] < '0' || s[i] > '9' {
        raise bad()
      }
      v = v * 10 + (s[i].to_int() - '0')
    }
    v
  }

  if n < 8 {
    raise bad()
  }
  let year = digits(0, 4)
  let month = digits(4, 2)
  let day = digits(6, 2)
  let mut i = 8
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  if i < n && s[i] == 'T' {
    i += 1
    let start = i
    while i < n && s[i] >= '0' && s[i] <= '9' {
      i += 1
    }
    match i - start {
      2 => hour = digits(start, 2)
      4 => {
        hour = digits(start, 2)
        minute = digits(start + 2, 2)
      }
      6 => {
        hour = digits(start, 2)
        minute = digits(start + 2, 2)
        second = digits(start + 4, 2)
      }
      _ => raise bad()
    }
  }
  let mut tz : @datetime.Tz? = None
  if i < n && s[i] == 'Z' {
    tz = Some(@tz.tzutc())
    i += 1
  }
  if i != n {
    raise bad()
  }
  let tz = if ignoretz { None } else { tz }
  @datetime.DateTime::new(year, month, day, hour~, minute~, second~, tzinfo?=tz) catch {
    _ => raise bad()
  }
}

///|
/// `tz.gettz(name)`, the default `tzids` lookup of `rrulestr`.
fn default_gettz(name : String) -> @datetime.Tz? raise {
  @tz.gettz(name~)
}
