///|
/// `tzutc`: the UTC time zone (a singleton, see `utc`/`tzutc()`).
priv struct TzUtc {}

///|
impl @datetime.TzInfo for TzUtc with fn utcoffset(_, _) {
  Some(@datetime.zero_timedelta)
}

///|
impl @datetime.TzInfo for TzUtc with fn dst(_, _) {
  Some(@datetime.zero_timedelta)
}

///|
impl @datetime.TzInfo for TzUtc with fn tzname(_, _) {
  Some("UTC")
}

///|
impl @datetime.TzInfo for TzUtc with fn is_ambiguous(_, _) {
  Some(false)
}

///|
/// Fast track: any valid UTC datetime is already the local time.
impl @datetime.TzInfo for TzUtc with fn fromutc(_, dt) {
  dt
}

///|
impl @datetime.TzInfo for TzUtc with fn repr(_) {
  "tzutc()"
}

///|
impl @datetime.TzInfo for TzUtc with fn eq_key(_) {
  Some(fixed_eq_key(@datetime.zero_timedelta))
}

///|
/// `tzutc == tzoffset(_, 0)` and `tzoffset(a, x) == tzoffset(b, x)`.
fn fixed_eq_key(offset : @datetime.TimeDelta) -> String {
  "\{fixed_key_prefix}\{offset.repr()}"
}

///|
let fixed_key_prefix : String = "dateutil.fixed:"

///|
/// `dateutil.tz.UTC`, the `tzutc()` singleton.
pub let utc : @datetime.Tz = @datetime.Tz::new(TzUtc::{ })

///|
/// `tzutc()`: always returns the same object, `utc`.
pub fn tzutc() -> @datetime.Tz {
  utc
}

///|
/// `tzoffset`: a fixed offset from UTC with an optional name.
priv struct TzOffset {
  name : String?
  offset : @datetime.TimeDelta
}

///|
impl @datetime.TzInfo for TzOffset with fn utcoffset(self, _) {
  Some(self.offset)
}

///|
impl @datetime.TzInfo for TzOffset with fn dst(_, _) {
  Some(@datetime.zero_timedelta)
}

///|
impl @datetime.TzInfo for TzOffset with fn tzname(self, _) {
  self.name
}

///|
impl @datetime.TzInfo for TzOffset with fn fromutc(self, dt) {
  dt.add(self.offset)
}

///|
impl @datetime.TzInfo for TzOffset with fn is_ambiguous(_, _) {
  Some(false)
}

///|
impl @datetime.TzInfo for TzOffset with fn repr(self) {
  let name = match self.name {
    None => "None"
    Some(n) => @datetime.py_str_repr(n)
  }
  "tzoffset(\{name}, \{self.offset.total_whole_seconds()})"
}

///|
impl @datetime.TzInfo for TzOffset with fn eq_key(self) {
  Some(fixed_eq_key(self.offset))
}

///|
let tzoffset_cache : Map[(String?, @datetime.TimeDelta), @datetime.Tz] = Map([])

///|
fn validate_offset(
  offset : @datetime.TimeDelta,
) -> Unit raise @datetime.DateTimeError {
  if offset.days < -1 ||
    offset.days >= 1 ||
    (offset.days == -1 && offset.seconds == 0 && offset.microseconds == 0) {
    raise @datetime.ValueError(
      "offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24).",
    )
  }
}

///|
/// `tzoffset(name, offset)` with the offset as a `TimeDelta`. Like
/// dateutil's factory, equal arguments return the same (cached) object.
pub fn tzoffset_delta(
  name : String?,
  offset : @datetime.TimeDelta,
) -> @datetime.Tz raise @datetime.DateTimeError {
  validate_offset(offset)
  let key = (name, offset)
  match tzoffset_cache.get(key) {
    Some(tz) => tz
    None => {
      let tz = @datetime.Tz::new(TzOffset::{ name, offset, })
      tzoffset_cache[key] = tz
      tz
    }
  }
}

///|
/// `tzoffset(name, seconds)`: a fixed offset of `seconds` east of UTC.
/// Equal arguments return the same (cached) object.
///
/// ```mbt check
/// test {
///   let brst = @tz.tzoffset(Some("BRST"), -10800)
///   inspect(brst, content="tzoffset('BRST', -10800)")
///   assert_true(@tz.tzoffset(Some("BRST"), -10800).is_same(brst))
///   assert_true(@tz.tzoffset(None, 0) == @tz.utc)
/// }
/// ```
pub fn tzoffset(
  name : String?,
  seconds : Int,
) -> @datetime.Tz raise @datetime.DateTimeError {
  tzoffset_delta(name, @datetime.TimeDelta::try_new(seconds~))
}

///|
/// `tzoffset.instance(name, offset)`: a fresh, uncached object.
pub fn tzoffset_instance(
  name : String?,
  offset : @datetime.TimeDelta,
) -> @datetime.Tz raise @datetime.DateTimeError {
  validate_offset(offset)
  @datetime.Tz::new(TzOffset::{ name, offset, })
}
