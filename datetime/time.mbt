///|
/// A time of day (Python `datetime.time`), optionally time zone aware.
pub struct Time {
  hour : Int
  minute : Int
  second : Int
  microsecond : Int
  tzinfo : Tz?
  fold : Int
}

///|
/// `time(hour, minute, second, microsecond, tzinfo, fold=fold)`.
pub fn Time::new(
  hour? : Int = 0,
  minute? : Int = 0,
  second? : Int = 0,
  microsecond? : Int = 0,
  tzinfo? : Tz,
  fold? : Int = 0,
) -> Time raise DateTimeError {
  check_time_fields(hour, minute, second, microsecond, fold)
  { hour, minute, second, microsecond, tzinfo, fold, }
}

///|
/// `time.replace(...)`. Pass `tzinfo=None` to drop the zone.
pub fn Time::replace(
  self : Time,
  hour? : Int,
  minute? : Int,
  second? : Int,
  microsecond? : Int,
  tzinfo? : Tz?,
  fold? : Int,
) -> Time raise DateTimeError {
  let tzinfo = match tzinfo {
    Some(t) => t
    None => self.tzinfo
  }
  let fold = fold.unwrap_or(self.fold)
  let hour = hour.unwrap_or(self.hour)
  let minute = minute.unwrap_or(self.minute)
  let second = second.unwrap_or(self.second)
  let microsecond = microsecond.unwrap_or(self.microsecond)
  check_time_fields(hour, minute, second, microsecond, fold)
  { hour, minute, second, microsecond, tzinfo, fold, }
}

///|
/// `time.utcoffset()`: asks the zone with a `None` datetime.
pub fn Time::utcoffset(self : Time) -> TimeDelta? {
  match self.tzinfo {
    None => None
    Some(tz) => tz.utcoffset(None)
  }
}

///|
pub fn Time::dst(self : Time) -> TimeDelta? {
  match self.tzinfo {
    None => None
    Some(tz) => tz.dst(None)
  }
}

///|
pub fn Time::tzname(self : Time) -> String? {
  match self.tzinfo {
    None => None
    Some(tz) => tz.tzname(None)
  }
}

///|
fn Time::cmp(
  self : Time,
  other : Time,
  allow_mixed : Bool,
) -> Int raise DateTimeError {
  let mut myoff = None
  let mut otoff = None
  let base_compare = if same_tz(self.tzinfo, other.tzinfo) {
    true
  } else {
    myoff = self.utcoffset()
    otoff = other.utcoffset()
    myoff == otoff
  }
  if base_compare {
    return compare_tuple4(
      (self.hour, self.minute, self.second, self.microsecond),
      (other.hour, other.minute, other.second, other.microsecond),
    )
  }
  guard myoff is Some(mo) && otoff is Some(oo) else {
    if allow_mixed {
      return 2
    }
    raise TypeError("cannot compare naive and aware times")
  }
  // Compare full UTC microseconds (CPython's C implementation; the
  // pure-Python reference truncates offsets to whole minutes).
  let mine = time_utc_us(self, mo)
  let theirs = time_utc_us(other, oo)
  mine.compare(theirs)
}

///|
fn time_utc_us(t : Time, off : TimeDelta) -> Int64 {
  (t.hour * 3600 + t.minute * 60 + t.second).to_int64() * 1000000L +
  t.microsecond.to_int64() -
  off.total_microseconds()
}

///|
fn compare_tuple4(a : (Int, Int, Int, Int), b : (Int, Int, Int, Int)) -> Int {
  let c = a.0.compare(b.0)
  if c != 0 {
    return c
  }
  let c = a.1.compare(b.1)
  if c != 0 {
    return c
  }
  let c = a.2.compare(b.2)
  if c != 0 {
    return c
  }
  a.3.compare(b.3)
}

///|
/// Ordering; raises `TypeError` when comparing naive and aware times.
pub fn Time::checked_compare(
  self : Time,
  other : Time,
) -> Int raise DateTimeError {
  self.cmp(other, false)
}

///|
/// Python `==` (naive vs aware compares unequal).
pub impl Eq for Time with fn equal(self, other) {
  (self.cmp(other, true) catch { _ => 2 }) == 0
}

///|
/// Python ordering. Aborts when comparing naive and aware times; use
/// `checked_compare` to handle that case.
pub impl Compare for Time with fn compare(self, other) {
  self.cmp(other, false) catch {
    e => abort(e.to_string())
  }
}

///|
pub impl Hash for Time with fn hash_combine(self, hasher) {
  let t = if self.fold != 0 { { ..self, fold: 0, } } else { self }
  match t.utcoffset() {
    None => {
      hasher.combine_int(t.hour)
      hasher.combine_int(t.minute)
      hasher.combine_int(t.second)
      hasher.combine_int(t.microsecond)
    }
    Some(off) => hasher.combine_int64(time_utc_us(t, off))
  }
}

///|
/// How much of the time to include in ISO 8601 output.
pub(all) enum TimeSpec {
  Auto
  Hours
  Minutes
  Seconds
  Milliseconds
  Microseconds
} derive(Eq, Debug)

///|
fn format_time(
  hh : Int,
  mm : Int,
  ss : Int,
  us : Int,
  timespec : TimeSpec,
) -> String {
  let spec = match timespec {
    Auto => if us != 0 { Microseconds } else { Seconds }
    s => s
  }
  match spec {
    Hours => pad(hh, 2)
    Minutes => "\{pad(hh, 2)}:\{pad(mm, 2)}"
    Seconds => "\{pad(hh, 2)}:\{pad(mm, 2)}:\{pad(ss, 2)}"
    Milliseconds =>
      "\{pad(hh, 2)}:\{pad(mm, 2)}:\{pad(ss, 2)}.\{pad(us / 1000, 3)}"
    _ => "\{pad(hh, 2)}:\{pad(mm, 2)}:\{pad(ss, 2)}.\{pad(us, 6)}"
  }
}

///|
/// `+HH:MM[:SS[.ffffff]]` (CPython `_format_offset`), empty for `None`.
pub fn format_utcoffset(off : TimeDelta?, sep? : String = ":") -> String {
  guard off is Some(off) else { return "" }
  let (sign, off) = if off.days < 0 { ("-", -off) } else { ("+", off) }
  let hh = off.seconds / 3600
  let mm = off.seconds % 3600 / 60
  let ss = off.seconds % 60
  let s = "\{sign}\{pad(hh, 2)}\{sep}\{pad(mm, 2)}"
  if ss != 0 || off.microseconds != 0 {
    let s = s + "\{sep}\{pad(ss, 2)}"
    if off.microseconds != 0 {
      s + ".\{pad(off.microseconds, 6)}"
    } else {
      s
    }
  } else {
    s
  }
}

///|
/// `time.isoformat(timespec)`.
pub fn Time::isoformat(self : Time, timespec? : TimeSpec = Auto) -> String {
  format_time(self.hour, self.minute, self.second, self.microsecond, timespec) +
  format_utcoffset(self.utcoffset())
}

///|
/// Python `str(time)`.
pub impl Show for Time with fn output(self, logger) {
  logger.write_string(self.isoformat())
}

///|
/// Python `repr(time)`.
pub fn Time::repr(self : Time) -> String {
  let s = if self.microsecond != 0 {
    "\{self.hour}, \{self.minute}, \{self.second}, \{self.microsecond}"
  } else if self.second != 0 {
    "\{self.hour}, \{self.minute}, \{self.second}"
  } else {
    "\{self.hour}, \{self.minute}"
  }
  let s = match self.tzinfo {
    Some(tz) => s + ", tzinfo=\{tz.repr()}"
    None => s
  }
  let s = if self.fold != 0 { s + ", fold=1" } else { s }
  "datetime.time(\{s})"
}
