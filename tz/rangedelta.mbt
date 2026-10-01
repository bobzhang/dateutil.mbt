// TEMPORARY stand-in for `@relativedelta.RelativeDelta` (being ported on
// another branch). It implements the integer subset of `relativedelta`
// that `tzrange`/`tzstr` need: construction (with `_fix` normalization and
// `yearday`/`nlyearday`), `bool()`, `==` and `datetime + relativedelta`.
// Once `relativedelta/` is merged, replace `TzRangeDelta` by
// `@relativedelta.RelativeDelta` and delete this file.

///|
/// Stand-in for `@relativedelta.RelativeDelta` in `tzrange` rules (the
/// integer subset; same constructor labels). Will be replaced by
/// `@relativedelta.RelativeDelta`.
pub struct TzRangeDelta {
  priv years : Int
  priv months : Int
  priv days : Int
  priv leapdays : Int
  priv hours : Int
  priv minutes : Int
  priv seconds : Int
  priv microseconds : Int
  priv year : Int?
  priv month : Int?
  priv day : Int?
  priv weekday : @datetime.Weekday?
  priv hour : Int?
  priv minute : Int?
  priv second : Int?
  priv microsecond : Int?
}

///|
/// Python `_sign`-based carry of `_fix`: move whole `unit`s of `value`
/// (keeping the sign) into the next larger field.
fn fix_carry(value : Int, limit : Int, unit : Int) -> (Int, Int) {
  if value.abs() > limit {
    let s = if value < 0 { -1 } else { 1 }
    let v = value * s
    (v % unit * s, v / unit * s)
  } else {
    (value, 0)
  }
}

///|
/// `relativedelta(...)` restricted to integer arguments (see the
/// `@relativedelta` package for the full type). Raises `ValueError` for an
/// invalid `yearday`/`nlyearday`.
pub fn TzRangeDelta::new(
  years? : Int = 0,
  months? : Int = 0,
  days? : Int = 0,
  leapdays? : Int = 0,
  weeks? : Int = 0,
  hours? : Int = 0,
  minutes? : Int = 0,
  seconds? : Int = 0,
  microseconds? : Int = 0,
  year? : Int,
  month? : Int,
  day? : Int,
  weekday? : @datetime.Weekday,
  yearday? : Int,
  nlyearday? : Int,
  hour? : Int,
  minute? : Int,
  second? : Int,
  microsecond? : Int,
) -> TzRangeDelta raise @datetime.DateTimeError {
  let mut month = month
  let mut day = day
  let mut leapdays = leapdays
  let mut yday = 0
  if nlyearday is Some(n) && n != 0 {
    yday = n
  } else if yearday is Some(y) && y != 0 {
    yday = y
    if y > 59 {
      leapdays = -1
    }
  }
  if yday != 0 {
    let ydayidx = [31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 366]
    for idx, ydays in ydayidx {
      if yday <= ydays {
        month = Some(idx + 1)
        day = Some(if idx == 0 { yday } else { yday - ydayidx[idx - 1] })
        break
      }
    } nobreak {
      raise @datetime.ValueError("invalid year day (\{yday})")
    }
  }
  let (microseconds, carry) = fix_carry(microseconds, 999999, 1000000)
  let (seconds, carry) = fix_carry(seconds + carry, 59, 60)
  let (minutes, carry) = fix_carry(minutes + carry, 59, 60)
  let (hours, carry) = fix_carry(hours + carry, 23, 24)
  let days = days + weeks * 7 + carry
  let (months, carry) = fix_carry(months, 11, 12)
  let years = years + carry
  {
    years,
    months,
    days,
    leapdays,
    hours,
    minutes,
    seconds,
    microseconds,
    year,
    month,
    day,
    weekday,
    hour,
    minute,
    second,
    microsecond,
  }
}

///|
/// Python `bool(relativedelta)`.
fn TzRangeDelta::to_bool(self : TzRangeDelta) -> Bool {
  !(self.years == 0 &&
  self.months == 0 &&
  self.days == 0 &&
  self.hours == 0 &&
  self.minutes == 0 &&
  self.seconds == 0 &&
  self.microseconds == 0 &&
  self.leapdays == 0 &&
  self.year is None &&
  self.month is None &&
  self.day is None &&
  self.weekday is None &&
  self.hour is None &&
  self.minute is None &&
  self.second is None &&
  self.microsecond is None)
}

///|
/// Canonical text of the fields compared by `relativedelta.__eq__` (a
/// weekday with `n` of `None`, `0` or `1` compares equal).
fn TzRangeDelta::fingerprint(self : TzRangeDelta) -> String {
  fn opt(v : Int?) -> String {
    match v {
      None => "_"
      Some(x) => x.to_string()
    }
  }

  let wd = match self.weekday {
    None => "_"
    Some({ weekday, n: None | Some(0) | Some(1), }) => "\{weekday}:1"
    Some({ weekday, n: Some(n), }) => "\{weekday}:\{n}"
  }
  "rd(\{self.years},\{self.months},\{self.days},\{self.leapdays},\{self.hours},\{self.minutes},\{self.seconds},\{self.microseconds},\{opt(self.year)},\{opt(self.month)},\{opt(self.day)},\{wd},\{opt(self.hour)},\{opt(self.minute)},\{opt(self.second)},\{opt(self.microsecond)})"
}

///|
/// Python `datetime + relativedelta`.
fn TzRangeDelta::add_to_datetime(
  self : TzRangeDelta,
  other : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  let mut year = (match self.year {
      Some(y) if y != 0 => y
      _ => other.year
    }) +
    self.years
  let mut month = match self.month {
    Some(m) if m != 0 => m
    _ => other.month
  }
  if self.months != 0 {
    month += self.months
    if month > 12 {
      year += 1
      month -= 12
    } else if month < 1 {
      year -= 1
      month += 12
    }
  }
  let want_day = match self.day {
    Some(d) if d != 0 => d
    _ => other.day
  }
  let ndays = @datetime.monthrange(year, month).1
  let day = if want_day < ndays { want_day } else { ndays }
  let replaced = other.replace(
    year~,
    month~,
    day~,
    hour?=self.hour,
    minute?=self.minute,
    second?=self.second,
    microsecond?=self.microsecond,
  )
  let mut days = self.days
  if self.leapdays != 0 && month > 2 && @datetime.is_leap(year) {
    days += self.leapdays
  }
  let ret = replaced.add(
    @datetime.TimeDelta::try_new(
      days~,
      hours=self.hours,
      minutes=self.minutes,
      seconds=self.seconds,
      microseconds=self.microseconds,
    ),
  )
  match self.weekday {
    None => ret
    Some({ weekday, n, }) => {
      let nth = match n {
        None | Some(0) => 1
        Some(n) => n
      }
      let mut jumpdays = (nth.abs() - 1) * 7
      if nth > 0 {
        jumpdays += @datetime.floor_mod(7 - ret.weekday() + weekday, 7)
      } else {
        jumpdays += @datetime.floor_mod(ret.weekday() - weekday, 7)
        jumpdays = -jumpdays
      }
      ret.add(@datetime.TimeDelta::try_new(days=jumpdays))
    }
  }
}
