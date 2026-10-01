///|
/// A date with time of day (Python `datetime.datetime`), optionally time
/// zone aware. Follows CPython semantics, including PEP 495 `fold`.
pub struct DateTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  microsecond : Int
  tzinfo : Tz?
  fold : Int
}

///|
/// `datetime(year, month, day, hour, minute, second, microsecond, tzinfo,
/// fold=fold)`; raises `ValueError` for out-of-range fields.
pub fn DateTime::new(
  year : Int,
  month : Int,
  day : Int,
  hour? : Int = 0,
  minute? : Int = 0,
  second? : Int = 0,
  microsecond? : Int = 0,
  tzinfo? : Tz,
  fold? : Int = 0,
) -> DateTime raise DateTimeError {
  check_date_fields(year, month, day)
  check_time_fields(hour, minute, second, microsecond, fold)
  { year, month, day, hour, minute, second, microsecond, tzinfo, fold, }
}

///|
/// `datetime.min`.
pub let min_datetime : DateTime = {
  year: 1,
  month: 1,
  day: 1,
  hour: 0,
  minute: 0,
  second: 0,
  microsecond: 0,
  tzinfo: None,
  fold: 0,
}

///|
/// `datetime.max`.
pub let max_datetime : DateTime = {
  year: 9999,
  month: 12,
  day: 31,
  hour: 23,
  minute: 59,
  second: 59,
  microsecond: 999999,
  tzinfo: None,
  fold: 0,
}

///|
/// `datetime.replace(...)`. Pass `tzinfo=None` to make the result naive and
/// `tzinfo=Some(tz)` to attach a zone without conversion.
pub fn DateTime::replace(
  self : DateTime,
  year? : Int,
  month? : Int,
  day? : Int,
  hour? : Int,
  minute? : Int,
  second? : Int,
  microsecond? : Int,
  tzinfo? : Tz?,
  fold? : Int,
) -> DateTime raise DateTimeError {
  let tzinfo = match tzinfo {
    Some(t) => t
    None => self.tzinfo
  }
  DateTime::new(
    year.unwrap_or(self.year),
    month.unwrap_or(self.month),
    day.unwrap_or(self.day),
    hour=hour.unwrap_or(self.hour),
    minute=minute.unwrap_or(self.minute),
    second=second.unwrap_or(self.second),
    microsecond=microsecond.unwrap_or(self.microsecond),
    tzinfo?,
    fold=fold.unwrap_or(self.fold),
  )
}

///|
/// Attach (or drop) a zone without converting; never fails.
pub fn DateTime::with_tzinfo(self : DateTime, tzinfo : Tz?) -> DateTime {
  { ..self, tzinfo, }
}

///|
/// Set the PEP 495 `fold` attribute (0 or 1); never fails.
pub fn DateTime::with_fold(self : DateTime, fold : Int) -> DateTime {
  { ..self, fold: if fold != 0 { 1 } else { 0 }, }
}

///|
/// `datetime.combine(date, time, tzinfo)`. The zone defaults to the
/// time's zone; pass `tzinfo=None` to force a naive result.
pub fn DateTime::combine(date : Date, time : Time, tzinfo? : Tz?) -> DateTime {
  let tzinfo = match tzinfo {
    Some(t) => t
    None => time.tzinfo
  }
  {
    year: date.year,
    month: date.month,
    day: date.day,
    hour: time.hour,
    minute: time.minute,
    second: time.second,
    microsecond: time.microsecond,
    tzinfo,
    fold: time.fold,
  }
}

///|
/// Midnight of `date` (naive).
pub fn Date::to_datetime(self : Date) -> DateTime {
  {
    year: self.year,
    month: self.month,
    day: self.day,
    hour: 0,
    minute: 0,
    second: 0,
    microsecond: 0,
    tzinfo: None,
    fold: 0,
  }
}

///|
/// `datetime.fromordinal(n)` (midnight, naive).
pub fn DateTime::from_ordinal(n : Int) -> DateTime raise DateTimeError {
  Date::from_ordinal(n).to_datetime()
}

///|
pub fn DateTime::date(self : DateTime) -> Date {
  { year: self.year, month: self.month, day: self.day, }
}

///|
/// The time part, without zone.
pub fn DateTime::time(self : DateTime) -> Time {
  {
    hour: self.hour,
    minute: self.minute,
    second: self.second,
    microsecond: self.microsecond,
    tzinfo: None,
    fold: self.fold,
  }
}

///|
/// The time part, with zone.
pub fn DateTime::timetz(self : DateTime) -> Time {
  { ..self.time(), tzinfo: self.tzinfo, }
}

///|
pub fn DateTime::to_ordinal(self : DateTime) -> Int {
  ymd_to_ordinal(self.year, self.month, self.day)
}

///|
/// Monday == 0 ... Sunday == 6.
pub fn DateTime::weekday(self : DateTime) -> Int {
  floor_mod(self.to_ordinal() + 6, 7)
}

///|
pub fn DateTime::isoweekday(self : DateTime) -> Int {
  self.weekday() + 1
}

///|
pub fn DateTime::isocalendar(self : DateTime) -> (Int, Int, Int) {
  iso_calendar_of(self.year, self.month, self.day)
}

///|
/// `datetime.utcoffset()`.
pub fn DateTime::utcoffset(self : DateTime) -> TimeDelta? {
  match self.tzinfo {
    None => None
    Some(tz) => tz.utcoffset(Some(self))
  }
}

///|
/// `datetime.dst()`.
pub fn DateTime::dst(self : DateTime) -> TimeDelta? {
  match self.tzinfo {
    None => None
    Some(tz) => tz.dst(Some(self))
  }
}

///|
/// `datetime.tzname()`.
pub fn DateTime::tzname(self : DateTime) -> String? {
  match self.tzinfo {
    None => None
    Some(tz) => tz.tzname(Some(self))
  }
}

///|
/// True if the datetime has a zone whose `utcoffset` is not `None`.
pub fn DateTime::is_aware(self : DateTime) -> Bool {
  self.utcoffset() is Some(_)
}

///|
/// `timetuple()`; `isdst` comes from `dst()`.
pub fn DateTime::timetuple(self : DateTime) -> TimeTuple {
  let isdst = match self.dst() {
    None => -1
    Some(d) => if d.is_zero() { 0 } else { 1 }
  }
  {
    year: self.year,
    month: self.month,
    day: self.day,
    hour: self.hour,
    minute: self.minute,
    second: self.second,
    weekday: self.weekday(),
    yday: days_before_month(self.year, self.month) + self.day,
    isdst,
  }
}

///|
/// `datetime + timedelta` (wall-clock arithmetic; the result has `fold=0`).
pub fn DateTime::add(
  self : DateTime,
  delta : TimeDelta,
) -> DateTime raise DateTimeError {
  let secs = self.hour.to_int64() * 3600L +
    self.minute.to_int64() * 60L +
    self.second.to_int64() +
    delta.seconds.to_int64()
  let us = self.microsecond.to_int64() + delta.microseconds.to_int64()
  let secs = secs + floor_div64(us, 1000000L)
  let us = floor_mod64(us, 1000000L)
  let days = self.to_ordinal().to_int64() +
    delta.days.to_int64() +
    floor_div64(secs, 86400L)
  let secs = floor_mod64(secs, 86400L).to_int()
  if days > 0L && days <= MAXORDINAL.to_int64() {
    let (year, month, day) = ordinal_to_ymd(days.to_int())
    {
      year,
      month,
      day,
      hour: secs / 3600,
      minute: secs % 3600 / 60,
      second: secs % 60,
      microsecond: us.to_int(),
      tzinfo: self.tzinfo,
      fold: 0,
    }
  } else {
    raise OverflowError("date value out of range")
  }
}

///|
/// `datetime - timedelta`.
pub fn DateTime::sub(
  self : DateTime,
  delta : TimeDelta,
) -> DateTime raise DateTimeError {
  self.add(delta.checked_neg())
}

///|
fn DateTime::naive_diff(self : DateTime, other : DateTime) -> TimeDelta {
  let days = self.to_ordinal() - other.to_ordinal()
  let secs1 = self.second + self.minute * 60 + self.hour * 3600
  let secs2 = other.second + other.minute * 60 + other.hour * 3600
  TimeDelta::new(
    days~,
    seconds=secs1 - secs2,
    microseconds=self.microsecond - other.microsecond,
  )
}

///|
/// `datetime - datetime`. Same-zone (identity) operands use wall time;
/// otherwise offsets are taken into account. Mixing naive and aware raises
/// `TypeError`.
pub fn DateTime::diff(
  self : DateTime,
  other : DateTime,
) -> TimeDelta raise DateTimeError {
  let base = self.naive_diff(other)
  if same_tz(self.tzinfo, other.tzinfo) {
    return base
  }
  let myoff = self.utcoffset()
  let otoff = other.utcoffset()
  if myoff == otoff {
    return base
  }
  guard myoff is Some(mo) && otoff is Some(oo) else {
    raise TypeError("cannot mix naive and timezone-aware time")
  }
  base.checked_add(oo).checked_sub(mo)
}

///|
fn DateTime::cmp(
  self : DateTime,
  other : DateTime,
  allow_mixed : Bool,
) -> Int raise DateTimeError {
  let mut myoff = None
  let mut otoff = None
  let base_compare = if same_tz(self.tzinfo, other.tzinfo) {
    true
  } else {
    myoff = self.utcoffset()
    otoff = other.utcoffset()
    // `allow_mixed` means we are called from `==`: PEP 495 says
    // datetimes whose offset depends on `fold` never compare equal to a
    // datetime in another zone.
    if allow_mixed {
      if myoff != self.with_fold(1 - self.fold).utcoffset() {
        return 2
      }
      if otoff != other.with_fold(1 - other.fold).utcoffset() {
        return 2
      }
    }
    myoff == otoff
  }
  if base_compare {
    let c = self.to_ordinal().compare(other.to_ordinal())
    if c != 0 {
      return c
    }
    return compare_tuple4(
      (self.hour, self.minute, self.second, self.microsecond),
      (other.hour, other.minute, other.second, other.microsecond),
    )
  }
  guard myoff is Some(mo) && otoff is Some(oo) else {
    if allow_mixed {
      return 2
    }
    raise TypeError("can't compare offset-naive and offset-aware datetimes")
  }
  let diff = self.naive_diff(other).checked_add(oo).checked_sub(mo)
  if diff.days < 0 {
    -1
  } else if diff.is_zero() {
    0
  } else {
    1
  }
}

///|
/// Python ordering; raises `TypeError` for naive vs aware operands.
pub fn DateTime::checked_compare(
  self : DateTime,
  other : DateTime,
) -> Int raise DateTimeError {
  self.cmp(other, false)
}

///|
/// Python `==`: never raises; naive vs aware compare unequal.
pub impl Eq for DateTime with fn equal(self, other) {
  (self.cmp(other, true) catch { _ => 2 }) == 0
}

///|
/// Python ordering. Aborts for naive vs aware operands (Python raises
/// `TypeError`); use `checked_compare` to handle that case.
pub impl Compare for DateTime with fn compare(self, other) {
  self.cmp(other, false) catch {
    e => abort(e.to_string())
  }
}

///|
/// Hash consistent with `==`: aware datetimes hash by UTC instant (using
/// the `fold=0` offset), naive ones by wall time.
pub impl Hash for DateTime with fn hash_combine(self, hasher) {
  let t = if self.fold != 0 { self.with_fold(0) } else { self }
  let days = t.to_ordinal().to_int64()
  let secs = days * 86400L +
    (t.hour * 3600 + t.minute * 60 + t.second).to_int64()
  match t.utcoffset() {
    None => {
      hasher.combine_int64(secs)
      hasher.combine_int(t.microsecond)
    }
    Some(off) => {
      let us = t.microsecond.to_int64() - off.microseconds.to_int64()
      let secs = secs - off.total_whole_seconds() + floor_div64(us, 1000000L)
      hasher.combine_int64(secs)
      hasher.combine_int64(floor_mod64(us, 1000000L))
    }
  }
}

///|
/// `datetime.astimezone(tz)`; with no argument converts to the system
/// local zone (as a fixed-offset `timezone`). Naive datetimes are assumed
/// to be in system local time.
pub fn DateTime::astimezone(
  self : DateTime,
  tz? : Tz,
) -> DateTime raise DateTimeError {
  let (mytz, myoffset) = match self.tzinfo {
    None => {
      let ltz = self.local_timezone()
      (ltz, ltz.utcoffset(Some(self)))
    }
    Some(mytz) =>
      match mytz.utcoffset(Some(self)) {
        Some(off) => (mytz, Some(off))
        None => {
          let ltz = self.with_tzinfo(None).local_timezone()
          (ltz, ltz.utcoffset(Some(self)))
        }
      }
  }
  let tz = match tz {
    Some(t) => t
    None => self.local_timezone()
  }
  if tz.is_same(mytz) {
    return self
  }
  guard myoffset is Some(myoffset) else {
    raise ValueError("astimezone(): local utcoffset() returned None")
  }
  let utc_dt = self.sub(myoffset).with_tzinfo(Some(tz))
  tz.fromutc(utc_dt)
}

///|
/// The system local zone at this instant as a fixed `timezone`
/// (CPython `_local_timezone`).
fn DateTime::local_timezone(self : DateTime) -> Tz raise DateTimeError {
  let ts = match self.tzinfo {
    None => {
      let ts = self.mktime()
      // Detect gap
      let ts2 = self.with_fold(1 - self.fold).mktime()
      if ts2 != ts && (ts2 > ts) == (self.fold == 1) {
        ts2
      } else {
        ts
      }
    }
    Some(_) => self.diff(epoch_aware).total_whole_seconds()
  }
  let lt = localtime(ts)
  Tz::fixed(TimeDelta::new(seconds=lt.gmtoff), name=lt.zone)
}

///|
let epoch_aware : DateTime = { ..min_datetime, year: 1970, tzinfo: Some(utc), }

///|
let epoch_naive : DateTime = { ..min_datetime, year: 1970, }

///|
fn naive_seconds_since_epoch(dt : DateTime) -> Int64 {
  dt.naive_diff(epoch_naive).total_whole_seconds()
}

///|
/// CPython `datetime._mktime`: solve `local(u) == t` for a naive local
/// datetime, honouring `fold` in ambiguous and imaginary times.
fn DateTime::mktime(self : DateTime) -> Int64 {
  let max_fold_seconds = 86400L
  let t = naive_seconds_since_epoch(self)
  fn local_secs(u : Int64) -> Int64 {
    let lt = localtime(u)
    let days = (ymd_to_ordinal(lt.year, lt.month, lt.day) -
    ymd_to_ordinal(1970, 1, 1)).to_int64()
    days * 86400L + (lt.hour * 3600 + lt.minute * 60 + lt.second).to_int64()
  }

  let a = local_secs(t) - t
  let u1 = t - a
  let t1 = local_secs(u1)
  let b = if t1 == t {
    let u2 = u1 +
      (if self.fold == 0 { -max_fold_seconds } else { max_fold_seconds })
    let b = local_secs(u2) - u2
    if a == b {
      return u1
    }
    b
  } else {
    t1 - u1
  }
  let u2 = t - b
  let t2 = local_secs(u2)
  if t2 == t {
    return u2
  }
  if t1 == t {
    return u1
  }
  if self.fold == 0 {
    if u1 > u2 {
      u1
    } else {
      u2
    }
  } else if u1 < u2 {
    u1
  } else {
    u2
  }
}

///|
/// POSIX timestamp. Naive datetimes are interpreted as system local time.
pub fn DateTime::timestamp(self : DateTime) -> Double raise DateTimeError {
  match self.tzinfo {
    None => self.mktime().to_double() + self.microsecond.to_double() / 1.0e6
    Some(_) => self.diff(epoch_aware).total_seconds()
  }
}

///|
fn utc_fields(
  t : Int64,
  us : Int,
  tzinfo : Tz?,
) -> DateTime raise DateTimeError {
  let days = floor_div64(t, 86400L)
  let secs = floor_mod64(t, 86400L).to_int()
  let ordinal = days + ymd_to_ordinal(1970, 1, 1).to_int64()
  if ordinal < 1L || ordinal > MAXORDINAL.to_int64() {
    raise ValueError("year is out of range")
  }
  let (year, month, day) = ordinal_to_ymd(ordinal.to_int())
  {
    year,
    month,
    day,
    hour: secs / 3600,
    minute: secs % 3600 / 60,
    second: secs % 60,
    microsecond: us,
    tzinfo,
    fold: 0,
  }
}

///|
fn local_fields(t : Int64, us : Int) -> DateTime raise DateTimeError {
  // Local offsets are within a day; keep the platform call in range.
  let days = floor_div64(t, 86400L) + ymd_to_ordinal(1970, 1, 1).to_int64()
  if days < 2L || days > MAXORDINAL.to_int64() - 1L {
    raise ValueError("year is out of range")
  }
  let lt = localtime(t)
  DateTime::new(
    lt.year,
    lt.month,
    lt.day,
    hour=lt.hour,
    minute=lt.minute,
    second=@cmp.minimum(lt.second, 59),
    microsecond=us,
  )
}

///|
fn split_timestamp(t : Double) -> (Int64, Int) raise DateTimeError {
  if t.is_nan() {
    raise ValueError("Invalid value NaN (not a number)")
  }
  if t.is_inf() || t.abs() > 1.0e15 {
    raise OverflowError("timestamp out of range for platform time_t")
  }
  let (frac, whole) = modf(t)
  let mut us = round_half_even(frac * 1.0e6).to_int()
  let mut t = whole.to_int64()
  if us >= 1000000 {
    t += 1L
    us -= 1000000
  } else if us < 0 {
    t -= 1L
    us += 1000000
  }
  (t, us)
}

///|
/// `datetime.fromtimestamp(t, tz)`. Without `tz` the result is naive
/// system local time (with `fold` detection like CPython).
pub fn DateTime::from_timestamp(
  t : Double,
  tz? : Tz,
) -> DateTime raise DateTimeError {
  let (t, us) = split_timestamp(t)
  match tz {
    Some(tz) => tz.fromutc(utc_fields(t, us, Some(tz)))
    None => local_from_timestamp(t, us)
  }
}

///|
/// Naive local time for a timestamp, with CPython's fold detection.
fn local_from_timestamp(t : Int64, us : Int) -> DateTime raise DateTimeError {
  let result = local_fields(t, us)
  let max_fold_seconds = 86400L
  let probe1 = local_fields(t - max_fold_seconds, us) catch {
    _ => return result
  }
  let trans = result
    .naive_diff(probe1)
    .checked_sub(TimeDelta::new(seconds=86400))
  if trans.days < 0 {
    let probe2 = local_fields(t + trans.total_whole_seconds(), us)
    if probe2 == result {
      return result.with_fold(1)
    }
  }
  result
}

///|
/// `datetime.utcfromtimestamp(t)` (naive UTC).
pub fn DateTime::utc_from_timestamp(t : Double) -> DateTime raise DateTimeError {
  let (t, us) = split_timestamp(t)
  utc_fields(t, us, None)
}

///|
/// `datetime.now(tz)`; naive local time when `tz` is omitted.
pub fn DateTime::now(tz? : Tz) -> DateTime {
  let ms = @env.now()
  let t = (ms / 1000UL).reinterpret_as_int64()
  let us = (ms % 1000UL).to_int() * 1000
  let r = try {
    match tz {
      Some(tz) => tz.fromutc(utc_fields(t, us, Some(tz)))
      None => local_from_timestamp(t, us)
    }
  } catch {
    e => abort(e.to_string())
  }
  r
}

///|
/// `datetime.utcnow()` (naive UTC).
pub fn DateTime::utcnow() -> DateTime {
  let ms = @env.now()
  let t = (ms / 1000UL).reinterpret_as_int64()
  let us = (ms % 1000UL).to_int() * 1000
  utc_fields(t, us, None) catch {
    e => abort(e.to_string())
  }
}

///|
/// `datetime.isoformat(sep, timespec)`.
pub fn DateTime::isoformat(
  self : DateTime,
  sep? : Char = 'T',
  timespec? : TimeSpec = Auto,
) -> String {
  "\{pad(self.year, 4)}-\{pad(self.month, 2)}-\{pad(self.day, 2)}\{sep}" +
  format_time(self.hour, self.minute, self.second, self.microsecond, timespec) +
  format_utcoffset(self.utcoffset())
}

///|
/// Python `str(datetime)`: `isoformat(sep=' ')`.
pub impl Show for DateTime with fn output(self, logger) {
  logger.write_string(self.isoformat(sep=' '))
}

///|
/// Python `repr(datetime)`, e.g.
/// `datetime.datetime(2003, 9, 25, 10, 49, 41, tzinfo=tzutc())`.
pub fn DateTime::repr(self : DateTime) -> String {
  let parts = [
    self.year,
    self.month,
    self.day,
    self.hour,
    self.minute,
    self.second,
    self.microsecond,
  ]
  let mut n = 7
  while n > 5 && parts[n - 1] == 0 {
    n -= 1
  }
  let s = parts[:n].map(x => x.to_string()).join(", ")
  let s = match self.tzinfo {
    Some(tz) => s + ", tzinfo=\{tz.repr()}"
    None => s
  }
  let s = if self.fold != 0 { s + ", fold=1" } else { s }
  "datetime.datetime(\{s})"
}

///|
/// `datetime.ctime()`.
pub fn DateTime::ctime(self : DateTime) -> String {
  ctime_of(self.year, self.month, self.day, self.hour, self.minute, self.second)
}
