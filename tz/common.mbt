// dateutil's `tz/_common.py`: the `_tzinfo` base-class behaviours as
// helpers that dateutil zones opt into from their `TzInfo` impls.

///|
/// `enfold(dt, fold)`: set the PEP 495 fold attribute (0 or 1).
pub fn enfold(dt : @datetime.DateTime, fold? : Int = 1) -> @datetime.DateTime {
  dt.with_fold(fold)
}

///|
/// dateutil `_tzinfo.is_ambiguous`: the wall time is ambiguous in `tz` if
/// its offset differs between `fold=0` and `fold=1`.
pub fn tzinfo_is_ambiguous(tz : @datetime.Tz, dt : @datetime.DateTime) -> Bool {
  let dt = dt.with_tzinfo(Some(tz))
  let wall_0 = enfold(dt, fold=0)
  let wall_1 = enfold(dt, fold=1)
  let same_offset = wall_0.utcoffset() == wall_1.utcoffset()
  // wall_0 and wall_1 always have the same naive fields
  !same_offset
}

///|
/// dateutil `_tzinfo._fold_status`. Uses the zone's own `is_ambiguous`
/// (falling back to `tzinfo_is_ambiguous` for zones without one), as
/// Python's `self.is_ambiguous` dispatches to subclass overrides.
pub fn tzinfo_fold_status(
  tz : @datetime.Tz,
  dt_utc : @datetime.DateTime,
  dt_wall : @datetime.DateTime,
) -> Int raise @datetime.DateTimeError {
  let ambiguous = match tz.is_ambiguous(dt_wall) {
    Some(b) => b
    None => tzinfo_is_ambiguous(tz, dt_wall)
  }
  if ambiguous {
    let delta_wall = dt_wall.diff(dt_utc)
    match (dt_utc.utcoffset(), dt_utc.dst()) {
      (Some(off), Some(dst)) => if delta_wall == off - dst { 1 } else { 0 }
      _ => 0
    }
  } else {
    0
  }
}

///|
/// dateutil `_tzinfo._fromutc`: CPython's algorithm, but defaulting to the
/// fold for ambiguous dates.
pub fn tzinfo_fromutc_naive(
  dt : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  guard dt.utcoffset() is Some(dtoff) else {
    raise @datetime.ValueError(
      "fromutc() requires a non-None utcoffset() result",
    )
  }
  guard dt.dst() is Some(dtdst) else {
    raise @datetime.ValueError("fromutc() requires a non-None dst() result")
  }
  let delta = dtoff - dtdst
  let dt = dt.add(delta)
  // Set fold=1 so we can default to being in the fold for ambiguous dates.
  guard enfold(dt, fold=1).dst() is Some(dtdst) else {
    raise @datetime.ValueError(
      "fromutc(): dt.dst gave inconsistent results; cannot convert",
    )
  }
  dt.add(dtdst)
}

///|
/// dateutil `_tzinfo.fromutc`: fold-aware conversion from UTC. `dt.tzinfo`
/// must be the handle wrapping the zone.
pub fn tzinfo_fromutc(
  dt : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  guard dt.tzinfo is Some(tz) else {
    raise @datetime.ValueError("dt.tzinfo is not self")
  }
  let dt_wall = tzinfo_fromutc_naive(dt)
  let fold = tzinfo_fold_status(tz, dt, dt_wall)
  enfold(dt_wall, fold~)
}
