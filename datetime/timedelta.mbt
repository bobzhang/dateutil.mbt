///|
/// A duration, normalized exactly like CPython's `datetime.timedelta`:
/// `-999999999 <= days <= 999999999`, `0 <= seconds < 86400`,
/// `0 <= microseconds < 1000000`.
pub struct TimeDelta {
  days : Int
  seconds : Int
  microseconds : Int
} derive(Eq, Compare, Hash)

///|
pub let max_timedelta_days : Int = 999999999

///|
fn TimeDelta::normalize64(
  d : Int64,
  s : Int64,
  us : Int64,
) -> TimeDelta raise DateTimeError {
  let s = s + floor_div64(us, 1000000L)
  let us = floor_mod64(us, 1000000L)
  let d = d + floor_div64(s, 86400L)
  let s = floor_mod64(s, 86400L)
  if d > 999999999L || d < -999999999L {
    raise OverflowError("days=\{d}; must have magnitude <= 999999999")
  }
  { days: d.to_int(), seconds: s.to_int(), microseconds: us.to_int(), }
}

///|
/// `timedelta(days, seconds, microseconds, milliseconds, minutes, hours, weeks)`
/// with integer arguments. Raises `OverflowError` if the result has more
/// than 999999999 days in magnitude.
pub fn TimeDelta::try_new(
  days? : Int = 0,
  seconds? : Int = 0,
  microseconds? : Int = 0,
  milliseconds? : Int = 0,
  minutes? : Int = 0,
  hours? : Int = 0,
  weeks? : Int = 0,
) -> TimeDelta raise DateTimeError {
  let d = days.to_int64() + weeks.to_int64() * 7L
  let s = seconds.to_int64() +
    minutes.to_int64() * 60L +
    hours.to_int64() * 3600L
  let us = microseconds.to_int64() + milliseconds.to_int64() * 1000L
  // Bring seconds and microseconds into range before they can overflow.
  let s = s + floor_div64(us, 1000000L)
  let us = floor_mod64(us, 1000000L)
  let d = d + floor_div64(s, 86400L)
  let s = floor_mod64(s, 86400L)
  TimeDelta::normalize64(d, s, us)
}

///|
/// Like `try_new` but aborts on overflow. Use it for literal durations that
/// are known to be in range.
pub fn TimeDelta::new(
  days? : Int = 0,
  seconds? : Int = 0,
  microseconds? : Int = 0,
  milliseconds? : Int = 0,
  minutes? : Int = 0,
  hours? : Int = 0,
  weeks? : Int = 0,
) -> TimeDelta {
  TimeDelta::try_new(
    days~,
    seconds~,
    microseconds~,
    milliseconds~,
    minutes~,
    hours~,
    weeks~,
  ) catch {
    e => abort(e.to_string())
  }
}

///|
/// `timedelta(...)` with floating point arguments, using the exact
/// normalization and half-even rounding algorithm of CPython.
pub fn TimeDelta::from_float(
  days? : Double = 0.0,
  seconds? : Double = 0.0,
  microseconds? : Double = 0.0,
  milliseconds? : Double = 0.0,
  minutes? : Double = 0.0,
  hours? : Double = 0.0,
  weeks? : Double = 0.0,
) -> TimeDelta raise DateTimeError {
  let days = days + weeks * 7.0
  let seconds = seconds + minutes * 60.0 + hours * 3600.0
  let microseconds = microseconds + milliseconds * 1000.0
  if days.is_nan() || seconds.is_nan() || microseconds.is_nan() {
    raise ValueError("cannot convert float NaN to integer")
  }
  if days.is_inf() || seconds.is_inf() || microseconds.is_inf() {
    raise OverflowError("cannot convert float infinity to integer")
  }
  let (dayfrac, days_whole) = modf(days)
  let (daysecondsfrac, daysecondswhole) = modf(dayfrac * 86400.0)
  let s = double_trunc_to_big(daysecondswhole)
  let d = double_trunc_to_big(days_whole)
  let (secondsfrac0, seconds_whole) = modf(seconds)
  let secondsfrac = secondsfrac0 + daysecondsfrac
  let (dd, ss) = big_divmod(double_trunc_to_big(seconds_whole), big(86400L))
  let d = d + dd
  let s = s + ss
  let usdouble = secondsfrac * 1.0e6
  let us = double_trunc_to_big(round_half_even(microseconds + usdouble))
  TimeDelta::from_big(d, s, us)
}

///|
/// The zero duration.
pub let zero_timedelta : TimeDelta = { days: 0, seconds: 0, microseconds: 0, }

///|
/// `timedelta.min`.
pub let min_timedelta : TimeDelta = {
  days: -999999999,
  seconds: 0,
  microseconds: 0,
}

///|
/// `timedelta.max`.
pub let max_timedelta : TimeDelta = {
  days: 999999999,
  seconds: 86399,
  microseconds: 999999,
}

///|
/// `timedelta.resolution` (one microsecond).
pub let resolution : TimeDelta = { days: 0, seconds: 0, microseconds: 1, }

///|
pub fn TimeDelta::is_zero(self : TimeDelta) -> Bool {
  self.days == 0 && self.seconds == 0 && self.microseconds == 0
}

///|
/// `timedelta.total_seconds()`.
pub fn TimeDelta::total_seconds(self : TimeDelta) -> Double {
  // Python divides the exact integer microsecond count by 10**6 with a
  // single correct rounding. Below 2**53 the conversion is exact so one
  // division matches; above it, splitting off the whole seconds keeps the
  // error far below half an ulp of the result.
  let secs = self.days.to_int64() * 86400L + self.seconds.to_int64()
  if secs.abs() < 9000000000L {
    let us = secs * 1000000L + self.microseconds.to_int64()
    us.to_double() / 1.0e6
  } else {
    secs.to_double() + self.microseconds.to_double() / 1.0e6
  }
}

///|
/// Total length in microseconds. Exact for `|days| < 100_000_000`
/// (about 273 000 years); larger magnitudes abort since they do not fit
/// in an `Int64`.
pub fn TimeDelta::total_microseconds(self : TimeDelta) -> Int64 {
  if self.days.abs() >= 106751991 {
    abort("timedelta too large for Int64 microseconds")
  }
  (self.days.to_int64() * 86400L + self.seconds.to_int64()) * 1000000L +
  self.microseconds.to_int64()
}

///|
/// Total length in whole seconds, rounded towards negative infinity.
pub fn TimeDelta::total_whole_seconds(self : TimeDelta) -> Int64 {
  self.days.to_int64() * 86400L + self.seconds.to_int64()
}

///|
pub fn TimeDelta::checked_add(
  self : TimeDelta,
  other : TimeDelta,
) -> TimeDelta raise DateTimeError {
  TimeDelta::normalize64(
    self.days.to_int64() + other.days.to_int64(),
    self.seconds.to_int64() + other.seconds.to_int64(),
    self.microseconds.to_int64() + other.microseconds.to_int64(),
  )
}

///|
pub fn TimeDelta::checked_sub(
  self : TimeDelta,
  other : TimeDelta,
) -> TimeDelta raise DateTimeError {
  TimeDelta::normalize64(
    self.days.to_int64() - other.days.to_int64(),
    self.seconds.to_int64() - other.seconds.to_int64(),
    self.microseconds.to_int64() - other.microseconds.to_int64(),
  )
}

///|
pub fn TimeDelta::checked_neg(
  self : TimeDelta,
) -> TimeDelta raise DateTimeError {
  TimeDelta::normalize64(
    -self.days.to_int64(),
    -self.seconds.to_int64(),
    -self.microseconds.to_int64(),
  )
}

///|
/// Multiply by an integer (`td * n`).
pub fn TimeDelta::checked_mul(
  self : TimeDelta,
  n : Int,
) -> TimeDelta raise DateTimeError {
  // |days * n| < 2**61, so the products cannot overflow Int64.
  let n = n.to_int64()
  TimeDelta::normalize64(
    self.days.to_int64() * n,
    self.seconds.to_int64() * n,
    self.microseconds.to_int64() * n,
  )
}

///|
/// Multiply by a float (`td * f`): exact rational product rounded half to
/// even, like CPython.
pub fn TimeDelta::mul_float(
  self : TimeDelta,
  f : Double,
) -> TimeDelta raise DateTimeError {
  if f.is_nan() {
    raise ValueError("cannot convert float NaN to integer")
  }
  if f.is_inf() {
    raise OverflowError("cannot convert float infinity to integer")
  }
  let (a, b) = as_integer_ratio(f)
  let us = big_divide_and_round(self.to_big_us() * a, b)
  TimeDelta::from_big(big(0L), big(0L), us)
}

///|
/// `td / n` for an integer `n`, rounding half to even.
pub fn TimeDelta::div_int(
  self : TimeDelta,
  n : Int,
) -> TimeDelta raise DateTimeError {
  if n == 0 {
    raise ValueError("integer division or modulo by zero")
  }
  let us = big_divide_and_round(self.to_big_us(), big(n.to_int64()))
  TimeDelta::from_big(big(0L), big(0L), us)
}

///|
/// `td // n` for an integer `n` (floor division).
pub fn TimeDelta::floor_div_int(
  self : TimeDelta,
  n : Int,
) -> TimeDelta raise DateTimeError {
  if n == 0 {
    raise ValueError("integer division or modulo by zero")
  }
  let (q, _) = big_divmod(self.to_big_us(), big(n.to_int64()))
  TimeDelta::from_big(big(0L), big(0L), q)
}

///|
/// `td1 // td2` (floor division of durations).
pub fn TimeDelta::floor_div(
  self : TimeDelta,
  other : TimeDelta,
) -> Int64 raise DateTimeError {
  if other.is_zero() {
    raise ValueError("integer division or modulo by zero")
  }
  let (q, _) = big_divmod(self.to_big_us(), other.to_big_us())
  q.to_int64()
}

///|
/// `td1 / td2` as a float.
pub fn TimeDelta::ratio(
  self : TimeDelta,
  other : TimeDelta,
) -> Double raise DateTimeError {
  if other.is_zero() {
    raise ValueError("division by zero")
  }
  let a = self.to_big_us()
  let b = other.to_big_us()
  let limit = big(9007199254740992L) // 2**53: exact conversion below this
  if a.compare(limit) < 0 &&
    a.compare(-limit) > 0 &&
    b.compare(limit) < 0 &&
    b.compare(-limit) > 0 {
    a.to_int64().to_double() / b.to_int64().to_double()
  } else {
    self.total_seconds() / other.total_seconds()
  }
}

///|
/// `abs(td)`.
pub fn TimeDelta::abs(self : TimeDelta) -> TimeDelta {
  if self.days < 0 {
    -self
  } else {
    self
  }
}

///|
pub impl Add for TimeDelta with fn add(self, other) {
  self.checked_add(other) catch {
    e => abort(e.to_string())
  }
}

///|
pub impl Sub for TimeDelta with fn sub(self, other) {
  self.checked_sub(other) catch {
    e => abort(e.to_string())
  }
}

///|
pub impl Neg for TimeDelta with fn neg(self) {
  self.checked_neg() catch {
    e => abort(e.to_string())
  }
}

///|
/// Python `str(timedelta)`, e.g. `-1 day, 23:59:59.999999`.
pub impl Show for TimeDelta with fn output(self, logger) {
  let mm = self.seconds / 60
  let ss = self.seconds % 60
  let hh = mm / 60
  let mm = mm % 60
  if self.days != 0 {
    let plural = if self.days.abs() != 1 { "s" } else { "" }
    logger.write_string("\{self.days} day\{plural}, ")
  }
  logger.write_string("\{hh}:\{pad(mm, 2)}:\{pad(ss, 2)}")
  if self.microseconds != 0 {
    logger.write_string(".\{pad(self.microseconds, 6)}")
  }
}

///|
/// Python `repr(timedelta)`, e.g. `datetime.timedelta(days=1, seconds=5)`.
pub fn TimeDelta::repr(self : TimeDelta) -> String {
  let args = []
  if self.days != 0 {
    args.push("days=\{self.days}")
  }
  if self.seconds != 0 {
    args.push("seconds=\{self.seconds}")
  }
  if self.microseconds != 0 {
    args.push("microseconds=\{self.microseconds}")
  }
  if args.is_empty() {
    args.push("0")
  }
  "datetime.timedelta(\{args.join(", ")})"
}
