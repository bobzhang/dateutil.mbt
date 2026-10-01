// dateutil `tz.datetime_exists`, `tz.datetime_ambiguous` and
// `tz.resolve_imaginary`.

///|
fn zone_for(
  dt : @datetime.DateTime,
  tz : @datetime.Tz?,
) -> @datetime.Tz raise @datetime.DateTimeError {
  match tz {
    Some(t) => t
    None =>
      match dt.tzinfo {
        Some(t) => t
        None =>
          raise @datetime.ValueError(
            "Datetime is naive and no time zone provided.",
          )
      }
  }
}

///|
/// `datetime_exists(dt, tz)`: whether the wall time of `dt` exists in
/// `tz` (default: `dt`'s own zone), i.e. survives a round trip through
/// UTC. Raises `ValueError` for a naive `dt` without `tz`.
///
/// ```mbt check
/// test {
///   let nyc = @tz.tzstr("EST5EDT,M3.2.0,M11.1.0")
///   let gap = @datetime.DateTime::new(2011, 3, 13, hour=2, minute=30)
///   assert_false(@tz.datetime_exists(gap, tz=nyc))
///   assert_true(@tz.datetime_exists(gap.replace(hour=3), tz=nyc))
/// }
/// ```
pub fn datetime_exists(
  dt : @datetime.DateTime,
  tz? : @datetime.Tz,
) -> Bool raise @datetime.DateTimeError {
  let tz = zone_for(dt, tz)
  let dt = dt.with_tzinfo(None)
  // This is essentially a test of whether or not the datetime can survive
  // a round trip to UTC.
  let dt_rt = dt.with_tzinfo(Some(tz)).astimezone(tz=utc).astimezone(tz~)
  dt == dt_rt.with_tzinfo(None)
}

///|
/// `datetime_ambiguous(dt, tz)`: whether the wall time of `dt` is
/// ambiguous in `tz` (default: `dt`'s own zone). Uses the zone's
/// `is_ambiguous` when it has one; otherwise checks whether the `fold`
/// attribute changes the UTC offset *or* the DST offset. Raises
/// `ValueError` for a naive `dt` without `tz`.
///
/// ```mbt check
/// test {
///   let nyc = @tz.tzstr("EST5EDT,M3.2.0,M11.1.0")
///   let fold = @datetime.DateTime::new(2011, 11, 6, hour=1, minute=30)
///   assert_true(@tz.datetime_ambiguous(fold, tz=nyc))
///   assert_false(@tz.datetime_ambiguous(fold.replace(hour=2), tz=nyc))
/// }
/// ```
pub fn datetime_ambiguous(
  dt : @datetime.DateTime,
  tz? : @datetime.Tz,
) -> Bool raise @datetime.DateTimeError {
  let tz = zone_for(dt, tz)
  // If a time zone defines its own "is_ambiguous" function, we'll use that.
  if tz.is_ambiguous(dt) is Some(b) {
    return b
  }
  // If it doesn't come out and tell us it's ambiguous, we'll just check if
  // the fold attribute has any effect on this particular date and time.
  let dt = dt.with_tzinfo(Some(tz))
  let wall_0 = enfold(dt, fold=0)
  let wall_1 = enfold(dt, fold=1)
  let same_offset = wall_0.utcoffset() == wall_1.utcoffset()
  let same_dst = wall_0.dst() == wall_1.dst()
  !(same_offset && same_dst)
}

///|
/// `resolve_imaginary(dt)`: if `dt` falls in a gap of its zone, shift it
/// forward by the size of the gap; otherwise return it unchanged. An
/// imaginary datetime is taken to be the wall time the zone would show
/// had the transition not occurred.
///
/// ```mbt check
/// test {
///   let nyc = @tz.tzstr("EST5EDT,M3.2.0,M11.1.0")
///   let dt = @datetime.DateTime::new(2017, 3, 12, hour=2, minute=30, tzinfo=nyc)
///   inspect(@tz.resolve_imaginary(dt), content="2017-03-12 03:30:00-04:00")
/// }
/// ```
pub fn resolve_imaginary(
  dt : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  if dt.tzinfo is Some(_) && !datetime_exists(dt) {
    let day = @datetime.TimeDelta::new(hours=24)
    let curr_offset = dt.add(day).utcoffset()
    let old_offset = dt.sub(day).utcoffset()
    guard curr_offset is Some(curr) && old_offset is Some(old) else {
      raise @datetime.TypeError(
        "unsupported operand type(s) for -: 'NoneType' and 'NoneType'",
      )
    }
    return dt.add(curr - old)
  }
  dt
}
