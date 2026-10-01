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
/// `datetime.timedelta(days=, hours=, minutes=, seconds=, microseconds=)`
/// with float arguments (CPython's exact C algorithm).
fn py_timedelta(
  days~ : Double,
  hours~ : Double,
  minutes~ : Double,
  seconds~ : Double,
  microseconds~ : Double,
) -> @datetime.TimeDelta raise @datetime.DateTimeError {
  @datetime.TimeDelta::from_float(
    days~,
    hours~,
    minutes~,
    seconds~,
    microseconds~,
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
  let mut year = base_year.to_int64() + self.years.to_int64()
  let mut month = match self.month {
    Some(m) if m != 0 => m
    _ => other.month
  }
  if self.months != 0 {
    month += self.months
    if month > 12 {
      year += 1L
      month -= 12
    } else if month < 1 {
      year -= 1L
      month += 12
    }
  }
  // Python ints are unbounded; such a year fails in `replace` anyway.
  let year = int64_to_int(year)
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
      let nth = nth.to_int64()
      let mut jumpdays = (nth.abs() - 1L) * 7L
      if nth > 0L {
        jumpdays += @datetime.floor_mod(7 - ret.weekday() + weekday, 7).to_int64()
      } else {
        jumpdays += @datetime.floor_mod(ret.weekday() - weekday, 7).to_int64()
        jumpdays = -jumpdays
      }
      if jumpdays.abs() > @datetime.max_timedelta_days.to_int64() {
        raise @datetime.OverflowError(
          "days=\{jumpdays}; must have magnitude <= 999999999",
        )
      }
      ret.add(@datetime.TimeDelta::try_new(days=jumpdays.to_int()))
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
  // `_set_months(months)` then `_fix()`: `build` performs the same split.
  RelativeDelta::build(
    years=0L,
    months=months.to_int64(),
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
