// Calendar arithmetic shared by Date / DateTime, following CPython's
// `datetime.py` and the `calendar` module. All helpers accept any year
// (not only MINYEAR..=MAXYEAR) so callers such as rrule can probe
// neighbouring years safely.

///|
/// Smallest year number allowed in a `Date` or `DateTime`.
pub const MINYEAR : Int = 1

///|
/// Largest year number allowed in a `Date` or `DateTime`.
pub const MAXYEAR : Int = 9999

///|
/// Ordinal of 9999-12-31.
pub const MAXORDINAL : Int = 3652059

///|
let days_in_month_table : FixedArray[Int] = [
  -1, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
]

///|
let days_before_month_table : FixedArray[Int] = [
  -1, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334,
]

///|
/// Floor division (Python `//`).
pub fn floor_div(a : Int, b : Int) -> Int {
  let q = a / b
  if a % b != 0 && (a < 0) != (b < 0) {
    q - 1
  } else {
    q
  }
}

///|
/// Floor modulo (Python `%`): the result has the sign of `b`.
pub fn floor_mod(a : Int, b : Int) -> Int {
  let r = a % b
  if r != 0 && (r < 0) != (b < 0) {
    r + b
  } else {
    r
  }
}

///|
fn floor_div64(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a % b != 0L && (a < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
fn floor_mod64(a : Int64, b : Int64) -> Int64 {
  let r = a % b
  if r != 0L && (r < 0L) != (b < 0L) {
    r + b
  } else {
    r
  }
}

///|
/// `calendar.isleap(year)`.
pub fn is_leap(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
/// Number of days in `month` of `year` (`month` in 1..=12).
pub fn days_in_month(year : Int, month : Int) -> Int {
  if month == 2 && is_leap(year) {
    29
  } else {
    days_in_month_table[month]
  }
}

///|
/// Number of days in `year` (365 or 366).
pub fn days_in_year(year : Int) -> Int {
  if is_leap(year) {
    366
  } else {
    365
  }
}

///|
/// Number of days before January 1st of `year` (proleptic Gregorian).
pub fn days_before_year(year : Int) -> Int {
  let y = year - 1
  y * 365 + floor_div(y, 4) - floor_div(y, 100) + floor_div(y, 400)
}

///|
/// Number of days in `year` preceding the first day of `month`.
pub fn days_before_month(year : Int, month : Int) -> Int {
  days_before_month_table[month] +
  (if month > 2 && is_leap(year) { 1 } else { 0 })
}

///|
/// Proleptic Gregorian ordinal, where 0001-01-01 is day 1.
pub fn ymd_to_ordinal(year : Int, month : Int, day : Int) -> Int {
  days_before_year(year) + days_before_month(year, month) + day
}

///|
let di400y : Int = 146097

///|
let di100y : Int = 36524

///|
let di4y : Int = 1461

///|
/// Inverse of `ymd_to_ordinal`: returns `(year, month, day)`.
pub fn ordinal_to_ymd(ordinal : Int) -> (Int, Int, Int) {
  let n0 = ordinal - 1
  let n400 = floor_div(n0, di400y)
  let n = floor_mod(n0, di400y)
  let year = n400 * 400 + 1
  let n100 = n / di100y
  let n = n % di100y
  let n4 = n / di4y
  let n = n % di4y
  let n1 = n / 365
  let n = n % 365
  let year = year + n100 * 100 + n4 * 4 + n1
  if n1 == 4 || n100 == 4 {
    return (year - 1, 12, 31)
  }
  let leapyear = n1 == 3 && (n4 != 24 || n100 == 3)
  let mut month = (n + 50) >> 5
  let mut preceding = days_before_month_table[month] +
    (if month > 2 && leapyear { 1 } else { 0 })
  if preceding > n {
    month -= 1
    preceding -= days_in_month_table[month] +
      (if month == 2 && leapyear { 1 } else { 0 })
  }
  (year, month, n - preceding + 1)
}

///|
/// Day of week for a date, Monday == 0 ... Sunday == 6
/// (`calendar.weekday`).
pub fn weekday_of(year : Int, month : Int, day : Int) -> Int {
  floor_mod(ymd_to_ordinal(year, month, day) + 6, 7)
}

///|
/// `calendar.monthrange(year, month)`: weekday of the first day of the
/// month and number of days in the month.
pub fn monthrange(year : Int, month : Int) -> (Int, Int) raise DateTimeError {
  if month < 1 || month > 12 {
    raise ValueError("bad month number \{month}; must be 1-12")
  }
  (weekday_of(year, month, 1), days_in_month(year, month))
}

///|
/// `calendar.timegm`: seconds since the epoch for a UTC broken-down time.
pub fn timegm(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
) -> Int64 {
  let days = (ymd_to_ordinal(year, month, 1) -
  ymd_to_ordinal(1970, 1, 1) +
  day -
  1).to_int64()
  ((days * 24L + hour.to_int64()) * 60L + minute.to_int64()) * 60L +
  second.to_int64()
}

///|
fn check_date_fields(
  year : Int,
  month : Int,
  day : Int,
) -> Unit raise DateTimeError {
  if year < MINYEAR || year > MAXYEAR {
    raise ValueError("year \{year} is out of range")
  }
  if month < 1 || month > 12 {
    raise ValueError("month must be in 1..12")
  }
  let dim = days_in_month(year, month)
  if day < 1 || day > dim {
    raise ValueError("day is out of range for month")
  }
}

///|
fn check_time_fields(
  hour : Int,
  minute : Int,
  second : Int,
  microsecond : Int,
  fold : Int,
) -> Unit raise DateTimeError {
  if hour < 0 || hour > 23 {
    raise ValueError("hour must be in 0..23")
  }
  if minute < 0 || minute > 59 {
    raise ValueError("minute must be in 0..59")
  }
  if second < 0 || second > 59 {
    raise ValueError("second must be in 0..59")
  }
  if microsecond < 0 || microsecond > 999999 {
    raise ValueError("microsecond must be in 0..999999")
  }
  if fold != 0 && fold != 1 {
    raise ValueError("fold must be either 0 or 1")
  }
}
