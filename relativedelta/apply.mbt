///|
/// The result of adding a `RelativeDelta` to a `Date`: Python returns a
/// `date` unless the delta has time information (`has_time()`), in which
/// case the date is first converted to a naive midnight `datetime`.
pub(all) enum DateOrDateTime {
  Date(@datetime.Date)
  DateTime(@datetime.DateTime)
} derive(Eq)

///|
/// The value as a `DateTime` (a `Date` becomes naive midnight).
pub fn DateOrDateTime::to_datetime(self : DateOrDateTime) -> @datetime.DateTime {
  match self {
    Date(d) => d.to_datetime()
    DateTime(dt) => dt
  }
}

///|
/// The calendar date part.
pub fn DateOrDateTime::date(self : DateOrDateTime) -> @datetime.Date {
  match self {
    Date(d) => d
    DateTime(dt) => dt.date()
  }
}

///|
/// Python `str()` of the wrapped value.
pub impl Show for DateOrDateTime with fn output(self, logger) {
  match self {
    Date(d) => logger.write_string(d.to_string())
    DateTime(dt) => logger.write_string(dt.to_string())
  }
}

///|
/// Python `repr()` of the wrapped value.
pub impl Debug for DateOrDateTime with fn to_repr(self) {
  match self {
    Date(d) => Repr(d.repr())
    DateTime(dt) => Repr(dt.repr())
  }
}

///|
pub extend DateOrDateTime with Show::{to_string, output}

///|
let us_per_second : Int64 = 1000000L

///|
let us_per_day : Int64 = 86400000000L

///|
fn checked_add64(a : Int64, b : Int64) -> Int64 raise @datetime.DateTimeError {
  let s = a + b
  if ((a ^ s) & (b ^ s)) < 0L {
    raise @datetime.OverflowError("date value out of range")
  }
  s
}

///|
/// CPython's `timedelta.__new__` accumulation (`accum`) of one argument:
/// the integral part is multiplied exactly, the fractional part in floating
/// point; the sub-microsecond leftover is collected in `leftover`.
fn accum(
  sofar : Int64,
  num : Double,
  factor : Int64,
  leftover : Ref[Double],
) -> Int64 raise @datetime.DateTimeError {
  if num.is_nan() {
    raise @datetime.ValueError("cannot convert float NaN to integer")
  }
  let intpart = num.trunc()
  let fracpart = num - intpart
  // Results this large are far outside the date range anyway.
  if intpart.abs() * factor.to_double() >= 9.0e18 {
    raise @datetime.OverflowError("date value out of range")
  }
  let sum = checked_add64(sofar, intpart.to_int64() * factor)
  if fracpart == 0.0 {
    return sum
  }
  let dnum = factor.to_double() * fracpart
  let intpart2 = dnum.trunc()
  leftover.val += dnum - intpart2
  checked_add64(sum, intpart2.to_int64())
}

///|
/// C `round()`: half away from zero.
fn c_round(x : Double) -> Double {
  if x < 0.0 {
    -(-x + 0.5).floor()
  } else {
    (x + 0.5).floor()
  }
}

///|
/// `datetime.timedelta(days=, hours=, minutes=, seconds=, microseconds=)`
/// with float arguments, using CPython's exact algorithm.
fn py_timedelta(
  days~ : Double,
  hours~ : Double,
  minutes~ : Double,
  seconds~ : Double,
  microseconds~ : Double,
) -> @datetime.TimeDelta raise @datetime.DateTimeError {
  let leftover = Ref(0.0)
  let mut x = 0L
  x = accum(x, microseconds, 1L, leftover)
  x = accum(x, seconds, us_per_second, leftover)
  x = accum(x, minutes, 60L * us_per_second, leftover)
  x = accum(x, hours, 3600L * us_per_second, leftover)
  x = accum(x, days, us_per_day, leftover)
  if leftover.val != 0.0 {
    let lo = leftover.val
    let mut whole_us = c_round(lo)
    if (whole_us - lo).abs() == 0.5 {
      // Exactly halfway: round half to even on the total.
      let is_odd = (x & 1L).to_double()
      whole_us = 2.0 * c_round((lo + is_odd) * 0.5) - is_odd
    }
    x = checked_add64(x, whole_us.to_int64())
  }
  let d = x / us_per_day
  let r = x % us_per_day
  let (d, r) = if r < 0L { (d - 1L, r + us_per_day) } else { (d, r) }
  @datetime.TimeDelta::try_new(
    days=d.to_int(),
    seconds=(r / us_per_second).to_int(),
    microseconds=(r % us_per_second).to_int(),
  )
}

///|
/// Python `relativedelta.__add__(datetime)`.
fn RelativeDelta::apply_datetime(
  self : RelativeDelta,
  other : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  // `self.year or other.year`: 0 counts as unset.
  let base_year = match self.year {
    Some(y) if y != 0 => y
    _ => other.year
  }
  let mut year = base_year + self.years
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
    days += self.leapdays.to_double()
  }
  let td = py_timedelta(
    days~,
    hours=self.hours,
    minutes=self.minutes,
    seconds=self.seconds,
    microseconds=self.microseconds,
  )
  let ret = replaced.add(td)
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

///|
/// Python `datetime + relativedelta` (or `relativedelta + datetime`).
///
/// Order of application: absolute `year`, `month`, `day` (clamped to the
/// month length), absolute time fields, then relative `years`/`months`,
/// then `leapdays` (if the resulting year is leap and month > 2), then the
/// relative days/time as a `timedelta`, and finally the `weekday` jump.
///
/// ```mbt check
/// test {
///   let dt = @datetime.DateTime::new(2018, 4, 9, hour=13, minute=37)
///   let rd = @relativedelta.RelativeDelta::new(
///     hours=25,
///     day=1,
///     weekday=@relativedelta.mo.nth(Some(1)),
///   )
///   inspect(rd.add_to_datetime(dt), content="2018-04-02 14:37:00")
/// }
/// ```
pub fn RelativeDelta::add_to_datetime(
  self : RelativeDelta,
  dt : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  self.apply_datetime(dt)
}

///|
/// Python `datetime - relativedelta`, i.e. `(-rd).add_to_datetime(dt)`.
pub fn RelativeDelta::sub_from_datetime(
  self : RelativeDelta,
  dt : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  (-self).apply_datetime(dt)
}

///|
/// Python `date + relativedelta`. The result is a `Date` unless the delta
/// `has_time()`, in which case the date is converted to a naive midnight
/// `DateTime` first (as in Python). Fractional `days` alone keep the result
/// a `Date` (only whole days of the resulting `timedelta` count).
pub fn RelativeDelta::add_to_date(
  self : RelativeDelta,
  d : @datetime.Date,
) -> DateOrDateTime raise @datetime.DateTimeError {
  let dt = self.apply_datetime(d.to_datetime())
  if self.has_time() {
    DateTime(dt)
  } else {
    Date(dt.date())
  }
}

///|
/// Python `date - relativedelta`, i.e. `(-rd).add_to_date(d)`.
pub fn RelativeDelta::sub_from_date(
  self : RelativeDelta,
  d : @datetime.Date,
) -> DateOrDateTime raise @datetime.DateTimeError {
  (-self).add_to_date(d)
}

///|
/// Python `_set_months`.
fn split_months(months : Int) -> (Int, Int) {
  if months.abs() > 11 {
    let s = if months < 0 { -1 } else { 1 }
    let m = months * s
    (m / 12 * s, m % 12 * s)
  } else {
    (0, months)
  }
}

///|
/// Python `relativedelta(dt1, dt2)`: the delta such that
/// `dt2 + delta == dt1`, with the largest possible whole number of months
/// (years/months first, then days and time). Raises `TypeError` when
/// mixing naive and aware datetimes.
///
/// ```mbt check
/// test {
///   let rd = @relativedelta.RelativeDelta::between(
///     @datetime.DateTime::new(2003, 1, 31, hour=23, minute=59, second=59),
///     @datetime.DateTime::new(2003, 3, 1),
///   )
///   inspect(rd, content="relativedelta(months=-1, seconds=-1)")
/// }
/// ```
pub fn RelativeDelta::between(
  dt1 : @datetime.DateTime,
  dt2 : @datetime.DateTime,
) -> RelativeDelta raise @datetime.DateTimeError {
  fn months_only(months : Int) -> RelativeDelta {
    let (years, months) = split_months(months)
    {
      years,
      months,
      days: 0.0,
      leapdays: 0,
      hours: 0.0,
      minutes: 0.0,
      seconds: 0.0,
      microseconds: 0.0,
      year: None,
      month: None,
      day: None,
      weekday: None,
      hour: None,
      minute: None,
      second: None,
      microsecond: None,
    }
  }

  let mut months = (dt1.year - dt2.year) * 12 + (dt1.month - dt2.month)
  let mut dtm = months_only(months).apply_datetime(dt2)
  // If we've overshot our target, make an adjustment.
  let (sign, increment) = if dt1.checked_compare(dt2) < 0 {
    (1, 1)
  } else {
    (-1, -1)
  }
  while dt1.checked_compare(dtm) * sign > 0 {
    months += increment
    dtm = months_only(months).apply_datetime(dt2)
  }
  let delta = dt1.diff(dtm)
  let (years, months) = split_months(months)
  RelativeDelta::build(
    years~,
    months~,
    days=0.0,
    leapdays=0,
    hours=0.0,
    minutes=0.0,
    seconds=delta.seconds.to_double() + delta.days.to_double() * 86400.0,
    microseconds=delta.microseconds.to_double(),
    year=None,
    month=None,
    day=None,
    weekday=None,
    hour=None,
    minute=None,
    second=None,
    microsecond=None,
  )
}

///|
/// `relativedelta(date1, date2)`. Python treats two dates like two naive
/// midnight datetimes; to diff a `Date` against a `DateTime`, convert the
/// date with `Date::to_datetime()` (Python's coercion).
pub fn RelativeDelta::between_dates(
  d1 : @datetime.Date,
  d2 : @datetime.Date,
) -> RelativeDelta raise @datetime.DateTimeError {
  RelativeDelta::between(d1.to_datetime(), d2.to_datetime())
}
