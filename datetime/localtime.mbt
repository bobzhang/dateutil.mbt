///|
/// Broken-down local time (C `struct tm`), as returned by `localtime`.
pub struct LocalTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  /// 1 if DST is in effect, 0 if not, -1 if unknown.
  isdst : Int
  /// Offset east of UTC in seconds (`tm_gmtoff`).
  gmtoff : Int
  /// Zone abbreviation (`tm_zone`).
  zone : String
} derive(Eq, Debug)

///|
/// `time.gmtime(t)`.
pub fn gmtime(t : Int64) -> LocalTime {
  let days = floor_div64(t, 86400L)
  let secs = floor_mod64(t, 86400L).to_int()
  let ordinal = days + ymd_to_ordinal(1970, 1, 1).to_int64()
  let (year, month, day) = if ordinal >= 1L && ordinal <= MAXORDINAL.to_int64() {
    ordinal_to_ymd(ordinal.to_int())
  } else {
    abort("timestamp out of range")
  }
  {
    year,
    month,
    day,
    hour: secs / 3600,
    minute: secs % 3600 / 60,
    second: secs % 60,
    isdst: 0,
    gmtoff: 0,
    zone: "UTC",
  }
}

///|
/// `time.localtime(t)` for the system time zone (honouring the `TZ`
/// environment variable after `tzset()` on native). On the wasm backends
/// there is no system zone and this is `gmtime`.
pub fn localtime(t : Int64) -> LocalTime {
  platform_localtime(t)
}

///|
/// `time.tzset()`: re-read the `TZ` environment variable (native only).
pub fn tzset() -> Unit {
  platform_tzset()
}

///|
/// The process-wide local zone description, computed like CPython's
/// `time` module does when `tm_gmtoff` is available.
pub struct LocalZone {
  /// Seconds *west* of UTC of standard time (`time.timezone`).
  timezone : Int
  /// Seconds west of UTC of daylight time (`time.altzone`).
  altzone : Int
  /// Whether the zone has DST (`time.daylight`).
  daylight : Bool
  /// `(standard name, daylight name)` (`time.tzname`).
  tzname : (String, String)
} derive(Eq, Debug)

///|
/// Probe January and July of the current year, as CPython's
/// `init_timezone` does.
pub fn local_zone() -> LocalZone {
  let year_secs = (365L * 24L + 6L) * 3600L
  let now = (@env.now() / 1000UL).reinterpret_as_int64()
  let t = now / year_secs * year_secs
  let jan = localtime(t)
  let jul = localtime(t + year_secs / 2L)
  let janzone = -jan.gmtoff
  let julzone = -jul.gmtoff
  if janzone < julzone {
    // DST is reversed in the southern hemisphere
    {
      timezone: julzone,
      altzone: janzone,
      daylight: janzone != julzone,
      tzname: (jul.zone, jan.zone),
    }
  } else {
    {
      timezone: janzone,
      altzone: julzone,
      daylight: janzone != julzone,
      tzname: (jan.zone, jul.zone),
    }
  }
}
