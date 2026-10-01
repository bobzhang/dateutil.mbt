// POSIX `TZ` strings as understood by the C library (glibc / tzcode) and
// by TZif footers (RFC 9636 section 3.3):
//
//   std offset [dst [offset] [,start[/time],end[/time]]]
//
// Offsets are *west* of UTC (`EST5` is UTC-5), abbreviations are three or
// more letters or `<...>`-quoted (`<+0330>`), rule dates are `Jn` (1..365,
// February 29 never counted), `n` (0..365) or `Mm.w.d`, and rule times may
// be negative or exceed 24 hours (up to 167, RFC 9636). A DST zone without
// rules uses the US rules `M3.2.0,M11.1.0`, as glibc does.
//
// This is deliberately *not* dateutil's `tzstr` grammar (which inverts the
// sign of `GMT+h` and accepts legacy formats).

///|
/// The day on which a DST rule fires.
pub(all) enum RuleDate {
  /// `Jn`: Julian day 1..=365, February 29 is never counted.
  Julian1(Int)
  /// `n`: zero-based day of the year 0..=365, counting February 29.
  Julian0(Int)
  /// `Mm.w.d`: day `weekday` (0 = Sunday) of week `week` (1..=5, 5 =
  /// last) of month `month`.
  MonthWeekDay(month~ : Int, week~ : Int, weekday~ : Int)
} derive(Eq, Debug)

///|
/// A transition rule: a date and a local time of day in seconds (which may
/// be negative or larger than a day).
pub(all) struct Rule {
  date : RuleDate
  time : Int
} derive(Eq, Debug)

///|
/// Daylight-saving part of a POSIX TZ string.
pub(all) struct DstSpec {
  abbr : String
  /// Seconds *east* of UTC.
  offset : Int
  /// Start of DST, in local standard time.
  start : Rule
  /// End of DST, in local daylight time.
  end : Rule
} derive(Eq, Debug)

///|
/// A parsed POSIX TZ string.
pub(all) struct PosixTz {
  std_abbr : String
  /// Seconds *east* of UTC (the negation of the string's offset).
  std_offset : Int
  dst : DstSpec?
} derive(Eq, Debug)

///|
priv struct Cursor {
  s : String
  mut pos : Int
}

///|
fn Cursor::peek(self : Cursor) -> Int {
  if self.pos < self.s.length() {
    self.s[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn Cursor::eat(self : Cursor, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn is_alpha(c : Int) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Int) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Abbreviation: `[A-Za-z]{3,}` or `<[A-Za-z0-9+-]{3,}>`.
fn Cursor::abbr(self : Cursor) -> String? {
  let start = self.pos
  if self.eat('<') {
    let inner = self.pos
    while self.peek() is c &&
          (is_alpha(c) || is_digit(c) || c == '+' || c == '-') {
      self.pos += 1
    }
    let end = self.pos
    if end - inner < 3 || !self.eat('>') {
      return None
    }
    Some(self.s.view(start_offset=inner, end_offset=end).to_owned())
  } else {
    while is_alpha(self.peek()) {
      self.pos += 1
    }
    if self.pos - start < 3 {
      return None
    }
    Some(self.s.view(start_offset=start, end_offset=self.pos).to_owned())
  }
}

///|
/// Unsigned decimal of 1..=`max_digits` digits.
fn Cursor::number(self : Cursor, max_digits : Int) -> Int? {
  let start = self.pos
  let mut n = 0
  while is_digit(self.peek()) && self.pos - start < max_digits {
    n = n * 10 + (self.peek() - '0')
    self.pos += 1
  }
  if self.pos == start {
    None
  } else {
    Some(n)
  }
}

///|
/// `[+-]hh[:mm[:ss]]` in seconds, with `hh <= max_hours`; positive unless
/// a `-` sign is given.
fn Cursor::hms(self : Cursor, max_hours : Int) -> Int? {
  let sign = if self.eat('-') {
    -1
  } else {
    ignore(self.eat('+'))
    1
  }
  guard self.number(3) is Some(h) && h <= max_hours else { return None }
  let mut total = h * 3600
  if self.eat(':') {
    guard self.number(2) is Some(m) && m <= 59 else { return None }
    total += m * 60
    if self.eat(':') {
      guard self.number(2) is Some(s) && s <= 59 else { return None }
      total += s
    }
  }
  Some(sign * total)
}

///|
fn Cursor::rule(self : Cursor) -> Rule? {
  let date = if self.eat('J') {
    guard self.number(3) is Some(n) && n >= 1 && n <= 365 else { return None }
    Julian1(n)
  } else if self.eat('M') {
    guard self.number(2) is Some(m) && m >= 1 && m <= 12 else { return None }
    guard self.eat('.') && self.number(1) is Some(w) && w >= 1 && w <= 5 else {
      return None
    }
    guard self.eat('.') && self.number(1) is Some(d) && d <= 6 else {
      return None
    }
    MonthWeekDay(month=m, week=w, weekday=d)
  } else {
    guard self.number(3) is Some(n) && n <= 365 else { return None }
    Julian0(n)
  }
  let time = if self.eat('/') {
    guard self.hms(167) is Some(t) else { return None }
    t
  } else {
    7200
  }
  Some({ date, time, })
}

///|
/// The rules glibc assumes for a DST zone given without rules
/// (`M3.2.0,M11.1.0`, both at 02:00).
pub let default_dst_rules : (Rule, Rule) = (
  { date: MonthWeekDay(month=3, week=2, weekday=0), time: 7200, },
  { date: MonthWeekDay(month=11, week=1, weekday=0), time: 7200, },
)

///|
/// Parse a POSIX TZ string; `None` if it is not valid.
///
/// ```mbt check
/// test {
///   guard @tzdata.parse_posix_tz("<+0330>-3:30") is Some(z) else { fail("") }
///   inspect(z.std_abbr, content="+0330")
///   inspect(z.std_offset, content="12600")
///   assert_true(@tzdata.parse_posix_tz("Europe/London") is None)
/// }
/// ```
pub fn parse_posix_tz(s : String) -> PosixTz? {
  let c = Cursor::{ s, pos: 0, }
  guard c.abbr() is Some(std_abbr) else { return None }
  guard c.hms(24) is Some(std_west) else { return None }
  let std_offset = -std_west
  if c.peek() == -1 {
    return Some({ std_abbr, std_offset, dst: None, })
  }
  guard c.abbr() is Some(dst_abbr) else { return None }
  let dst_offset = if c.peek() is ('+' | '-' | '0'..='9') {
    guard c.hms(24) is Some(w) else { return None }
    -w
  } else {
    std_offset + 3600
  }
  let (start, end) = if c.eat(',') {
    guard c.rule() is Some(start) else { return None }
    guard c.eat(',') && c.rule() is Some(end) else { return None }
    (start, end)
  } else {
    default_dst_rules
  }
  if c.peek() != -1 {
    return None
  }
  Some({
    std_abbr,
    std_offset,
    dst: Some({ abbr: dst_abbr, offset: dst_offset, start, end, }),
  })
}

///|
/// Seconds since the epoch, *as local wall time*, at which `rule` fires in
/// `year`.
fn Rule::local_epoch(self : Rule, year : Int64) -> Int64 {
  let days = match self.date {
    Julian1(n) => {
      let yday = if is_leap(year) && n >= 60 { n } else { n - 1 }
      days_from_civil(year, 1, 1) + yday.to_int64()
    }
    Julian0(n) => days_from_civil(year, 1, 1) + n.to_int64()
    MonthWeekDay(month~, week~, weekday~) => {
      let first = days_from_civil(year, month, 1)
      let first_wd = weekday_from_days(first)
      let mut mday = 1 + (weekday - first_wd + 7) % 7 + (week - 1) * 7
      let dim = days_in_month(year, month)
      while mday > dim {
        mday -= 7
      }
      first + (mday - 1).to_int64()
    }
  }
  days * 86400L + self.time.to_int64()
}

///|
/// The local time type in effect at `t` (seconds since the epoch, UTC).
///
/// DST starts at `start` (local standard time) and ends at `end` (local
/// daylight time). The rules for the UTC year of `t` and its neighbours are
/// evaluated, so rule times beyond a day, southern-hemisphere rules
/// (`start` after `end`) and all-year DST (`EST5EDT,0/0,J365/25`) work.
pub fn PosixTz::lookup(self : PosixTz, t : Int64) -> TimeType {
  let std : TimeType = {
    offset: self.std_offset,
    isdst: false,
    abbr: self.std_abbr,
  }
  guard self.dst is Some(dst) else { return std }
  let dst_type : TimeType = { offset: dst.offset, isdst: true, abbr: dst.abbr, }
  // Rules repeat every 400 years: move `t` into 1970..2370 so that the
  // arithmetic below cannot overflow for any Int64 timestamp.
  let t = floor_mod(t, cycle_seconds)
  let (year, _, _) = civil_from_days(floor_div(t, 86400L))
  fn start_utc(y : Int64) {
    dst.start.local_epoch(y) - self.std_offset.to_int64()
  }

  fn end_utc(y : Int64) {
    dst.end.local_epoch(y) - dst.offset.to_int64()
  }

  if start_utc(year) == end_utc(year) {
    // coincident transitions: an empty DST interval (glibc)
    return std
  }
  let northern = start_utc(year) < end_utc(year)
  let mut inside = false
  for y in (year - 1L)..<=(year + 1L) {
    let s = start_utc(y)
    let e = end_utc(y)
    if northern {
      if s <= t && t < e {
        inside = true
      }
    } else if e <= t && t < s {
      inside = true
    }
  }
  if northern == inside {
    dst_type
  } else {
    std
  }
}
