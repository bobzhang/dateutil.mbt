///|
/// dateutil's `relativedelta`: a duration expressed in calendar units
/// (relative fields, plural) plus optional absolute replacements
/// (absolute fields, singular).
///
/// Relative fields that Python allows to be fractional (`days`, `hours`,
/// `minutes`, `seconds`, `microseconds`) are stored as `Double` and keep
/// their fractional part until `normalized()` or application, exactly like
/// Python. `years`, `months` and `leapdays` are integers. Absolute fields are
/// `None` when unset.
///
/// Values are normalized on construction like Python's `_fix`:
/// `|microseconds| <= 999999`, `|seconds| <= 59`, `|minutes| <= 59`,
/// `|hours| <= 23`, `|months| <= 11` (carrying into the next larger unit
/// with the sign of the value), while `days` is unbounded.
pub struct RelativeDelta {
  years : Int
  months : Int
  mut days : Double
  leapdays : Int
  hours : Double
  minutes : Double
  seconds : Double
  microseconds : Double
  year : Int?
  month : Int?
  day : Int?
  weekday : @datetime.Weekday?
  hour : Int?
  minute : Int?
  second : Int?
  microsecond : Int?
}

///|
/// Python `relativedelta.__init__` keyword path (no `yearday`) followed by
/// `_fix()`. `years`/`months` are taken as `Int64` so that sums cannot wrap;
/// raises `OverflowError` if the normalized `years` does not fit an `Int`.
fn RelativeDelta::build(
  years~ : Int64,
  months~ : Int64,
  days~ : Double,
  leapdays~ : Int,
  hours~ : Double,
  minutes~ : Double,
  seconds~ : Double,
  microseconds~ : Double,
  year~ : Int?,
  month~ : Int?,
  day~ : Int?,
  weekday~ : @datetime.Weekday?,
  hour~ : Int?,
  minute~ : Int?,
  second~ : Int?,
  microsecond~ : Int?,
) -> RelativeDelta raise @datetime.DateTimeError {
  let mut years = years
  let mut months = months
  let mut days = days
  let mut hours = hours
  let mut minutes = minutes
  let mut seconds = seconds
  let mut microseconds = microseconds
  if microseconds.abs() > 999999.0 {
    let s = py_sign(microseconds)
    let (div, mod) = py_divmod_nonneg(microseconds * s, 1000000.0)
    microseconds = mod * s
    seconds += div * s
  }
  if seconds.abs() > 59.0 {
    let s = py_sign(seconds)
    let (div, mod) = py_divmod_nonneg(seconds * s, 60.0)
    seconds = mod * s
    minutes += div * s
  }
  if minutes.abs() > 59.0 {
    let s = py_sign(minutes)
    let (div, mod) = py_divmod_nonneg(minutes * s, 60.0)
    minutes = mod * s
    hours += div * s
  }
  if hours.abs() > 23.0 {
    let s = py_sign(hours)
    let (div, mod) = py_divmod_nonneg(hours * s, 24.0)
    hours = mod * s
    days += div * s
  }
  if months.abs() > 11L {
    let s = if months < 0L { -1L } else { 1L }
    let m = months * s
    months = m % 12L * s
    years += m / 12L * s
  }
  {
    years: int64_to_int(years),
    months: months.to_int(),
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
/// `relativedelta(years=..., months=..., ...)` with integer relative fields.
///
/// * Relative (plural) fields are added to a date when the delta is applied;
///   `weeks` is folded into `days`.
/// * Absolute (singular) fields replace the corresponding component.
/// * `weekday` moves forward/backward to the n-th given weekday (`n = None`
///   or `0` means `+1`).
/// * `yearday` / `nlyearday` set `month`/`day` (and `leapdays = -1` for a
///   `yearday > 59`); raises `ValueError` if the day is greater than 366.
///
/// Use `from_float` for fractional relative values.
///
/// ```mbt check
/// test {
///   let rd = @relativedelta.RelativeDelta::new(months=14, seconds=-25)
///   inspect(rd, content="relativedelta(years=+1, months=+2, seconds=-25)")
///   let rd = @relativedelta.RelativeDelta::new(
///     day=31,
///     weekday=@relativedelta.fr.nth(Some(-1)),
///   )
///   let d = @datetime.Date::new(2003, 9, 17)
///   inspect(rd.add_to_date(d), content="2003-09-26")
/// }
/// ```
pub fn RelativeDelta::new(
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
) -> RelativeDelta raise @datetime.DateTimeError {
  RelativeDelta::from_float(
    years=years.to_double(),
    months=months.to_double(),
    days=days.to_double(),
    leapdays~,
    weeks=weeks.to_double(),
    hours=hours.to_double(),
    minutes=minutes.to_double(),
    seconds=seconds.to_double(),
    microseconds=microseconds.to_double(),
    year?,
    month?,
    day?,
    weekday?,
    yearday?,
    nlyearday?,
    hour?,
    minute?,
    second?,
    microsecond?,
  )
}

///|
/// `relativedelta(...)` with float relative fields. `days`, `weeks`,
/// `hours`, `minutes`, `seconds` and `microseconds` keep their fractional
/// part until `normalized()` or application. `years` and `months` must be
/// integral (Python raises `ValueError` otherwise).
///
/// ```mbt check
/// test {
///   let rd = @relativedelta.RelativeDelta::from_float(days=1.5, hours=2.0)
///   inspect(rd, content="relativedelta(days=+1.5, hours=+2)")
///   inspect(rd.normalized(), content="relativedelta(days=+1, hours=+14)")
/// }
/// ```
pub fn RelativeDelta::from_float(
  years? : Double = 0.0,
  months? : Double = 0.0,
  days? : Double = 0.0,
  leapdays? : Int = 0,
  weeks? : Double = 0.0,
  hours? : Double = 0.0,
  minutes? : Double = 0.0,
  seconds? : Double = 0.0,
  microseconds? : Double = 0.0,
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
) -> RelativeDelta raise @datetime.DateTimeError {
  let years_i = py_int64(years)
  let months_i = py_int64(months)
  if years_i.to_double() != years || months_i.to_double() != months {
    raise @datetime.ValueError(
      "Non-integer years and months are ambiguous and not currently supported.",
    )
  }
  let mut leapdays = leapdays
  let mut month = month
  let mut day = day
  let yday = match (nlyearday, yearday) {
    (Some(n), _) if n != 0 => n
    (_, Some(y)) if y != 0 => {
      if y > 59 {
        leapdays = -1
      }
      y
    }
    _ => 0
  }
  if yday != 0 {
    let ydayidx = [31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 366]
    guard ydayidx.search_by(ydays => yday <= ydays) is Some(idx) else {
      raise @datetime.ValueError("invalid year day (\{yday})")
    }
    month = Some(idx + 1)
    day = Some(if idx == 0 { yday } else { yday - ydayidx[idx - 1] })
  }
  RelativeDelta::build(
    years=years_i,
    months=months_i,
    days=days + weeks * 7.0,
    leapdays~,
    hours~,
    minutes~,
    seconds~,
    microseconds~,
    year~,
    month~,
    day~,
    weekday~,
    hour~,
    minute~,
    second~,
    microsecond~,
  )
}

///|
/// Python's `_has_time`: whether applying this delta to a `date` produces a
/// `datetime` (some relative time field is non-zero or an absolute time
/// field is set). Fractional `days` do not count.
pub fn RelativeDelta::has_time(self : RelativeDelta) -> Bool {
  self.hours != 0.0 ||
  self.minutes != 0.0 ||
  self.seconds != 0.0 ||
  self.microseconds != 0.0 ||
  self.hour is Some(_) ||
  self.minute is Some(_) ||
  self.second is Some(_) ||
  self.microsecond is Some(_)
}

///|
/// The `weeks` property: `int(days / 7.0)` (truncated toward zero).
pub fn RelativeDelta::weeks(self : RelativeDelta) -> Int {
  (self.days / 7.0).trunc().to_int()
}

///|
/// The `weeks` property setter: replaces the whole-weeks part of `days`
/// (`days = days - weeks * 7 + value * 7`), in place.
pub fn RelativeDelta::set_weeks(self : RelativeDelta, value : Int) -> Unit {
  self.days = self.days -
    (self.days / 7.0).trunc() * 7.0 +
    value.to_double() * 7.0
}

///|
/// A copy with the given relative fields replaced (absolute fields kept),
/// run through the constructor normalization.
fn RelativeDelta::with_relative(
  self : RelativeDelta,
  years~ : Int64,
  months~ : Int64,
  days~ : Double,
  hours~ : Double,
  minutes~ : Double,
  seconds~ : Double,
  microseconds~ : Double,
) -> RelativeDelta raise @datetime.DateTimeError {
  RelativeDelta::build(
    years~,
    months~,
    days~,
    leapdays=self.leapdays,
    hours~,
    minutes~,
    seconds~,
    microseconds~,
    year=self.year,
    month=self.month,
    day=self.day,
    weekday=self.weekday,
    hour=self.hour,
    minute=self.minute,
    second=self.second,
    microsecond=self.microsecond,
  )
}

///|
/// Python `normalized()`: an equivalent delta whose relative fields are
/// all integers (fractions are cascaded down to microseconds, rounding
/// like Python, then carried back up).
///
/// ```mbt check
/// test {
///   let rd = @relativedelta.RelativeDelta::from_float(days=1.48)
///   inspect(
///     rd.normalized(),
///     content="relativedelta(days=+1, hours=+11, minutes=+31, seconds=+12)",
///   )
/// }
/// ```
pub fn RelativeDelta::normalized(
  self : RelativeDelta,
) -> RelativeDelta raise @datetime.DateTimeError {
  let days = py_int_float(self.days)
  let hours_f = py_round_ndigits(self.hours + 24.0 * (self.days - days), 11)
  let hours = py_int_float(hours_f)
  let minutes_f = py_round_ndigits(self.minutes + 60.0 * (hours_f - hours), 10)
  let minutes = py_int_float(minutes_f)
  let seconds_f = py_round_ndigits(
    self.seconds + 60.0 * (minutes_f - minutes),
    8,
  )
  let seconds = py_int_float(seconds_f)
  let microseconds = py_int_float(
    @datetime.round_half_even(self.microseconds + 1.0e6 * (seconds_f - seconds)),
  )
  self.with_relative(
    years=self.years.to_int64(),
    months=self.months.to_int64(),
    days~,
    hours~,
    minutes~,
    seconds~,
    microseconds~,
  )
}
