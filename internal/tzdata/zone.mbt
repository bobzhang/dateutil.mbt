///|
/// A system time zone: TZif data or a POSIX TZ string.
pub(all) enum Zone {
  TzifZone(Tzif)
  PosixZone(PosixTz)
} derive(Eq, Debug)

///|
/// UTC with abbreviation `"UTC"` (the fallback for unresolvable `TZ`).
pub let utc : Zone = PosixZone({ std_abbr: "UTC", std_offset: 0, dst: None, })

///|
/// The local time type (offset east of UTC, DST flag, abbreviation) in
/// effect at `t` seconds since the epoch, for any `Int64` `t`.
///
/// ```mbt check
/// test {
///   guard @tzdata.parse_posix_tz("EST5EDT,M3.2.0,M11.1.0") is Some(p) else {
///     fail("bad TZ string")
///   }
///   let z = @tzdata.PosixZone(p)
///   debug_inspect(
///     z.lookup(1720000000L), // 2024-07-03
///     content=(
///       #|{ offset: -14400, isdst: true, abbr: "EDT" }
///     ),
///   )
/// }
/// ```
pub fn Zone::lookup(self : Zone, t : Int64) -> TimeType {
  match self {
    TzifZone(z) => z.lookup(t)
    PosixZone(p) => p.lookup(t)
  }
}
