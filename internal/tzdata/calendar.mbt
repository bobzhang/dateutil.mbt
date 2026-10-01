// Proleptic Gregorian calendar arithmetic on day numbers relative to the
// Unix epoch (1970-01-01 = day 0), valid for any `Int64` year that does
// not overflow (H. Hinnant's `days_from_civil` / `civil_from_days`).

///|
fn floor_div(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a % b != 0L && (a < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
fn floor_mod(a : Int64, b : Int64) -> Int64 {
  a - floor_div(a, b) * b
}

///|
/// Seconds in a 400-year Gregorian cycle (146097 days); every calendar
/// rule repeats with this period.
let cycle_seconds : Int64 = 146097L * 86400L

///|
/// Whether `year` is a Gregorian leap year.
pub fn is_leap(year : Int64) -> Bool {
  year % 4L == 0L && (year % 100L != 0L || year % 400L == 0L)
}

///|
/// Number of days in `month` (1..=12) of `year`.
pub fn days_in_month(year : Int64, month : Int) -> Int {
  match month {
    2 => if is_leap(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
/// Days since 1970-01-01 of the civil date `year-month-day`.
///
/// ```mbt check
/// test {
///   inspect(@tzdata.days_from_civil(1970, 1, 1), content="0")
///   inspect(@tzdata.days_from_civil(2000, 3, 1), content="11017")
///   inspect(@tzdata.days_from_civil(1, 1, 1), content="-719162")
/// }
/// ```
pub fn days_from_civil(year : Int64, month : Int, day : Int) -> Int64 {
  let y = if month <= 2 { year - 1L } else { year }
  let era = floor_div(y, 400L)
  let yoe = y - era * 400L // [0, 399]
  let mp = ((month + 9) % 12).to_int64() // March = 0
  let doy = (153L * mp + 2L) / 5L + day.to_int64() - 1L // [0, 365]
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy // [0, 146096]
  era * 146097L + doe - 719468L
}

///|
/// The civil date `(year, month, day)` of a day number (days since
/// 1970-01-01).
///
/// ```mbt check
/// test {
///   debug_inspect(@tzdata.civil_from_days(0), content="(1970, 1, 1)")
///   debug_inspect(@tzdata.civil_from_days(-1), content="(1969, 12, 31)")
///   debug_inspect(@tzdata.civil_from_days(11016), content="(2000, 2, 29)")
/// }
/// ```
pub fn civil_from_days(days : Int64) -> (Int64, Int, Int) {
  let z = days + 719468L
  let era = floor_div(z, 146097L)
  let doe = z - era * 146097L // [0, 146096]
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L // [0, 399]
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L) // [0, 365]
  let mp = (5L * doy + 2L) / 153L // [0, 11]
  let day = (doy - (153L * mp + 2L) / 5L + 1L).to_int()
  let month = if mp < 10L { mp.to_int() + 3 } else { mp.to_int() - 9 }
  let year = yoe + era * 400L + (if month <= 2 { 1L } else { 0L })
  (year, month, day)
}

///|
/// Day of the week of a day number, `0` = Sunday (POSIX `tm_wday`).
pub fn weekday_from_days(days : Int64) -> Int {
  // 1970-01-01 was a Thursday
  floor_mod(days + 4L, 7L).to_int()
}

///|
/// Broken-down civil time of `t` seconds since the epoch, read as UTC:
/// `(year, month, day, hour, minute, second)`.
///
/// ```mbt check
/// test {
///   debug_inspect(
///     @tzdata.civil_from_seconds(-1L),
///     content="(1969, 12, 31, 23, 59, 59)",
///   )
/// }
/// ```
pub fn civil_from_seconds(t : Int64) -> (Int64, Int, Int, Int, Int, Int) {
  let days = floor_div(t, 86400L)
  let secs = floor_mod(t, 86400L).to_int()
  let (y, m, d) = civil_from_days(days)
  (y, m, d, secs / 3600, secs % 3600 / 60, secs % 60)
}
