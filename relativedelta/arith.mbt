///|
fn[T] first_some(a : T?, b : T?) -> T? {
  match a {
    Some(_) => a
    None => b
  }
}

///|
/// `rd1 + rd2`: relative fields are summed; for absolute fields and
/// `leapdays` the right operand wins when set (Python
/// `other.x if other.x is not None else self.x`, `other.leapdays or
/// self.leapdays`).
pub impl Add for RelativeDelta with fn add(self, other) {
  RelativeDelta::build(
    years=other.years + self.years,
    months=other.months + self.months,
    days=other.days + self.days,
    leapdays=if other.leapdays != 0 { other.leapdays } else { self.leapdays },
    hours=other.hours + self.hours,
    minutes=other.minutes + self.minutes,
    seconds=other.seconds + self.seconds,
    microseconds=other.microseconds + self.microseconds,
    year=first_some(other.year, self.year),
    month=first_some(other.month, self.month),
    day=first_some(other.day, self.day),
    weekday=first_some(other.weekday, self.weekday),
    hour=first_some(other.hour, self.hour),
    minute=first_some(other.minute, self.minute),
    second=first_some(other.second, self.second),
    microsecond=first_some(other.microsecond, self.microsecond),
  )
}

///|
/// `rd1 - rd2`: relative fields are subtracted; for absolute fields and
/// `leapdays` the *left* operand wins when set (as in Python).
pub impl Sub for RelativeDelta with fn sub(self, other) {
  RelativeDelta::build(
    years=self.years - other.years,
    months=self.months - other.months,
    days=self.days - other.days,
    leapdays=if self.leapdays != 0 { self.leapdays } else { other.leapdays },
    hours=self.hours - other.hours,
    minutes=self.minutes - other.minutes,
    seconds=self.seconds - other.seconds,
    microseconds=self.microseconds - other.microseconds,
    year=first_some(self.year, other.year),
    month=first_some(self.month, other.month),
    day=first_some(self.day, other.day),
    weekday=first_some(self.weekday, other.weekday),
    hour=first_some(self.hour, other.hour),
    minute=first_some(self.minute, other.minute),
    second=first_some(self.second, other.second),
    microsecond=first_some(self.microsecond, other.microsecond),
  )
}

///|
/// `-rd`: negates the relative fields (not `leapdays`, nor absolute fields).
pub impl Neg for RelativeDelta with fn neg(self) {
  self.with_relative(
    years=-self.years,
    months=-self.months,
    days=-self.days,
    hours=-self.hours,
    minutes=-self.minutes,
    seconds=-self.seconds,
    microseconds=-self.microseconds,
  )
}

///|
/// `abs(rd)`: absolute value of each relative field (not `leapdays`).
pub fn RelativeDelta::abs(self : RelativeDelta) -> RelativeDelta {
  self.with_relative(
    years=self.years.abs(),
    months=self.months.abs(),
    days=self.days.abs(),
    hours=self.hours.abs(),
    minutes=self.minutes.abs(),
    seconds=self.seconds.abs(),
    microseconds=self.microseconds.abs(),
  )
}

///|
/// `rd + timedelta`: adds the timedelta's `days`, `seconds` and
/// `microseconds` to the relative fields.
pub fn RelativeDelta::add_timedelta(
  self : RelativeDelta,
  td : @datetime.TimeDelta,
) -> RelativeDelta {
  self.with_relative(
    years=self.years,
    months=self.months,
    days=self.days + td.days.to_double(),
    hours=self.hours,
    minutes=self.minutes,
    seconds=self.seconds + td.seconds.to_double(),
    microseconds=self.microseconds + td.microseconds.to_double(),
  )
}

///|
/// `rd * f` (and `f * rd`): each relative field becomes `int(field * f)`
/// (truncated toward zero), so the result has integral relative fields.
/// `leapdays` and absolute fields are kept. Raises like Python's `int()`
/// for NaN/infinite products, and `OverflowError` if `years`/`months` no
/// longer fit an `Int`.
pub fn RelativeDelta::mul(
  self : RelativeDelta,
  f : Double,
) -> RelativeDelta raise @datetime.DateTimeError {
  fn trunc(x : Double) -> Double raise @datetime.DateTimeError {
    if x.is_nan() {
      raise @datetime.ValueError("cannot convert float NaN to integer")
    }
    if x.is_inf() {
      raise @datetime.OverflowError("cannot convert float infinity to integer")
    }
    x.trunc() + 0.0
  }

  self.with_relative(
    years=py_int(self.years.to_double() * f),
    months=py_int(self.months.to_double() * f),
    days=trunc(self.days * f),
    hours=trunc(self.hours * f),
    minutes=trunc(self.minutes * f),
    seconds=trunc(self.seconds * f),
    microseconds=trunc(self.microseconds * f),
  )
}

///|
/// `rd / f`: `rd * (1 / f)`. Division by zero raises `ValueError` (Python
/// raises `ZeroDivisionError`).
pub fn RelativeDelta::div(
  self : RelativeDelta,
  f : Double,
) -> RelativeDelta raise @datetime.DateTimeError {
  if f == 0.0 {
    raise @datetime.ValueError("float division by zero")
  }
  self.mul(1.0 / f)
}

///|
/// Python `bool(rd)`: false only when every relative field is zero and
/// every absolute field (including `weekday`) is unset.
pub fn RelativeDelta::to_bool(self : RelativeDelta) -> Bool {
  !(self.years == 0 &&
  self.months == 0 &&
  self.days == 0.0 &&
  self.hours == 0.0 &&
  self.minutes == 0.0 &&
  self.seconds == 0.0 &&
  self.microseconds == 0.0 &&
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
/// Weekday occurrence as compared by `__eq__`: `None`, `0` and `1` are all
/// "the next occurrence".
fn weekday_key(w : @datetime.Weekday?) -> (Int, Int)? {
  match w {
    None => None
    Some({ weekday, n: None | Some(0) | Some(1), }) => Some((weekday, 1))
    Some({ weekday, n: Some(n), }) => Some((weekday, n))
  }
}

///|
/// Python `__eq__`: field-wise equality, except that a weekday with
/// `n = None`, `0` or `1` compares equal to the same weekday with any of
/// those `n`.
pub impl Eq for RelativeDelta with fn equal(self, other) {
  weekday_key(self.weekday) == weekday_key(other.weekday) &&
  self.years == other.years &&
  self.months == other.months &&
  self.days == other.days &&
  self.hours == other.hours &&
  self.minutes == other.minutes &&
  self.seconds == other.seconds &&
  self.microseconds == other.microseconds &&
  self.leapdays == other.leapdays &&
  self.year == other.year &&
  self.month == other.month &&
  self.day == other.day &&
  self.hour == other.hour &&
  self.minute == other.minute &&
  self.second == other.second &&
  self.microsecond == other.microsecond
}

///|
/// Hash consistent with `Eq` (unlike Python, whose hash distinguishes
/// `MO` from `MO(+1)` although they compare equal; `-0.0` and `0.0` hash
/// alike as in Python).
pub impl Hash for RelativeDelta with fn hash_combine(self, hasher) {
  hasher.combine(weekday_key(self.weekday))
  hasher.combine(self.years)
  hasher.combine(self.months)
  hasher.combine(self.days + 0.0)
  hasher.combine(self.hours + 0.0)
  hasher.combine(self.minutes + 0.0)
  hasher.combine(self.seconds + 0.0)
  hasher.combine(self.microseconds + 0.0)
  hasher.combine(self.leapdays)
  hasher.combine(self.year)
  hasher.combine(self.month)
  hasher.combine(self.day)
  hasher.combine(self.hour)
  hasher.combine(self.minute)
  hasher.combine(self.second)
  hasher.combine(self.microsecond)
}

///|
/// Python `repr()`, e.g. `relativedelta(years=+1, months=-1, days=+15)` or
/// `relativedelta(month=3, weekday=SU(+3), hour=3)`. Relative fields use
/// Python's `{:+g}` format.
pub fn RelativeDelta::repr(self : RelativeDelta) -> String {
  let parts : Array[String] = []
  fn rel(name : String, value : Double) {
    if value != 0.0 {
      parts.push("\{name}=\{py_format_plus_g(value)}")
    }
  }

  fn abs_(name : String, value : Int?) {
    if value is Some(v) {
      parts.push("\{name}=\{v}")
    }
  }

  rel("years", self.years.to_double())
  rel("months", self.months.to_double())
  rel("days", self.days)
  rel("leapdays", self.leapdays.to_double())
  rel("hours", self.hours)
  rel("minutes", self.minutes)
  rel("seconds", self.seconds)
  rel("microseconds", self.microseconds)
  abs_("year", self.year)
  abs_("month", self.month)
  abs_("day", self.day)
  if self.weekday is Some(w) {
    parts.push("weekday=\{w}")
  }
  abs_("hour", self.hour)
  abs_("minute", self.minute)
  abs_("second", self.second)
  abs_("microsecond", self.microsecond)
  "relativedelta(\{parts.join(", ")})"
}

///|
/// Python `str()` (same as `repr()`).
pub impl Show for RelativeDelta with fn output(self, logger) {
  logger.write_string(self.repr())
}

///|
pub impl Debug for RelativeDelta with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub extend RelativeDelta with Show::{to_string, output}
