// dateutil `tzlocal`: the system local zone, built on `@datetime.localtime`
// (Python `time.localtime`) and the `time.timezone`/`altzone`/`daylight`/`tzname` values.

///|
priv struct TzLocal {
  std_offset : @datetime.TimeDelta
  dst_offset : @datetime.TimeDelta
  dst_saved : @datetime.TimeDelta
  hasdst : Bool
  tznames : (String, String)
}

///|
fn TzLocal::new() -> TzLocal {
  let zone = @datetime.local_zone()
  let std_offset = @datetime.TimeDelta::new(seconds=-zone.timezone)
  let dst_offset = if zone.daylight {
    @datetime.TimeDelta::new(seconds=-zone.altzone)
  } else {
    std_offset
  }
  let dst_saved = dst_offset - std_offset
  {
    std_offset,
    dst_offset,
    dst_saved,
    hasdst: !dst_saved.is_zero(),
    tznames: zone.tzname,
  }
}

///|
/// `time.localtime(timestamp + time.timezone).tm_isdst`, with the
/// datetime's wall time read as a UTC timestamp.
fn naive_is_dst(dt : @datetime.DateTime) -> Int {
  let timestamp = naive_timestamp_floor(dt)
  let timezone = @datetime.local_zone().timezone
  @datetime.localtime(timestamp + timezone.to_int64()).isdst
}

///|
/// dateutil `tzlocal.is_ambiguous`; `None` if `dt - dst_saved` overflows
/// (Python raises `OverflowError`).
fn TzLocal::is_ambiguous_opt(self : TzLocal, dt : @datetime.DateTime) -> Bool? {
  let naive_dst = naive_is_dst(dt)
  if naive_dst != 0 {
    return Some(false)
  }
  let earlier = dt.sub(self.dst_saved) catch { _ => return None }
  Some(naive_dst != naive_is_dst(earlier))
}

///|
fn TzLocal::isdst(self : TzLocal, dt : @datetime.DateTime?) -> Bool {
  if !self.hasdst {
    return false
  }
  guard dt is Some(dt) else { return false }
  // Check for ambiguous times:
  let dstval = naive_is_dst(dt)
  if self.is_ambiguous_opt(dt) is Some(true) {
    return dt.fold == 0
  }
  dstval != 0
}

///|
impl @datetime.TzInfo for TzLocal with fn utcoffset(self, dt) {
  if dt is None && self.hasdst {
    return None
  }
  if self.isdst(dt) {
    Some(self.dst_offset)
  } else {
    Some(self.std_offset)
  }
}

///|
impl @datetime.TzInfo for TzLocal with fn dst(self, dt) {
  if dt is None && self.hasdst {
    return None
  }
  if self.isdst(dt) {
    Some(self.dst_offset - self.std_offset)
  } else {
    Some(@datetime.zero_timedelta)
  }
}

///|
/// For a `time` (no date) in a zone with DST Python fails; this returns
/// `None`.
impl @datetime.TzInfo for TzLocal with fn tzname(self, dt) {
  if dt is None && self.hasdst {
    return None
  }
  if self.isdst(dt) {
    Some(self.tznames.1)
  } else {
    Some(self.tznames.0)
  }
}

///|
impl @datetime.TzInfo for TzLocal with fn fromutc(_, dt) {
  tzinfo_fromutc(dt)
}

///|
impl @datetime.TzInfo for TzLocal with fn is_ambiguous(self, dt) {
  self.is_ambiguous_opt(dt)
}

///|
impl @datetime.TzInfo for TzLocal with fn repr(_) {
  "tzlocal()"
}

///|
/// Fingerprint of a local zone: its standard and DST offsets (what
/// `tzlocal == tzlocal` compares).
impl @datetime.TzInfo for TzLocal with fn eq_key(self) {
  Some(tzlocal_key(self.std_offset, self.dst_offset))
}

///|
fn tzlocal_key(
  std_offset : @datetime.TimeDelta,
  dst_offset : @datetime.TimeDelta,
) -> String {
  "dateutil.tzlocal:\{std_offset.repr()},\{dst_offset.repr()}"
}

///|
/// Python `tzlocal.__eq__`: equal to another `tzlocal` with the same
/// offsets; to `tzutc` if there is no DST, the standard name is `UTC` or
/// `GMT` and the offset is zero; to a `tzoffset` with the same name and
/// offset if there is no DST. Anything else is `NotImplemented`.
impl @datetime.TzInfo for TzLocal with fn eq_with(self, other) {
  guard other.eq_key() is Some(key) else { return None }
  if key.has_prefix("dateutil.tzlocal:") {
    return Some(key == tzlocal_key(self.std_offset, self.dst_offset))
  }
  if !key.has_prefix(fixed_key_prefix) {
    return None
  }
  // A dateutil fixed-offset zone: `tzutc` or `tzoffset`.
  let repr = other.repr()
  if repr == "tzutc()" {
    Some(
      !self.hasdst &&
      (self.tznames.0 == "UTC" || self.tznames.0 == "GMT") &&
      self.std_offset.is_zero(),
    )
  } else {
    Some(
      !self.hasdst &&
      other.tzname(None) == Some(self.tznames.0) &&
      other.utcoffset(None) == Some(self.std_offset),
    )
  }
}

///|
/// `tzlocal()`: the system local time zone, described by
/// `@datetime.localtime` / `@datetime.local_zone` at construction time
/// (honouring `TZ` after `@datetime.tzset()` on every backend). Each call
/// returns a new zone.
///
/// ```mbt check
/// test {
///   inspect(@tz.tzlocal(), content="tzlocal()")
///   assert_true(@tz.tzlocal() == @tz.tzlocal())
/// }
/// ```
pub fn tzlocal() -> @datetime.Tz {
  @datetime.Tz::new(TzLocal::new())
}
