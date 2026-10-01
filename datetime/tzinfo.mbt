///|
/// The abstract time zone protocol, mirroring Python's `datetime.tzinfo`.
///
/// Implementations are wrapped in a `Tz` handle (which provides object
/// identity) before being attached to a `DateTime` or `Time`.
///
/// Every method receives the datetime being queried, or `None` when the
/// query comes from a `Time` object (Python calls `tzinfo.utcoffset(None)`
/// in that case). Methods are always invoked through the `Tz` handle, which
/// first attaches itself to the argument: inside an implementation,
/// `dt.tzinfo` is the handle wrapping this zone (Python's `self`), so
/// implementations may call `dt.utcoffset()` and friends on derived values
/// and pass `dt.tzinfo` to helpers that need the zone object.
pub(open) trait TzInfo {
  /// Offset of local time from UTC (positive east of UTC); `None` if unknown.
  /// Must be strictly between -24h and +24h.
  fn utcoffset(Self, DateTime?) -> TimeDelta?
  /// DST adjustment already included in `utcoffset`; `None` if unknown.
  fn dst(Self, DateTime?) -> TimeDelta?
  /// Abbreviated zone name, e.g. `EST`.
  fn tzname(Self, DateTime?) -> String?
  /// Convert a datetime whose wall fields are UTC (and whose `tzinfo` is the
  /// handle wrapping this zone) into local wall time in this zone.
  /// The default is CPython's `tzinfo.fromutc`.
  fn fromutc(Self, DateTime) -> DateTime raise DateTimeError = _
  /// dateutil's `is_ambiguous` extension. `None` means the zone does not
  /// support the query (a plain Python `tzinfo`), which is the default.
  fn is_ambiguous(Self, DateTime) -> Bool? = _
  /// Python `repr()` of the zone, e.g. `tzutc()`.
  fn repr(Self) -> String
  /// Canonical fingerprint used for zone *value* equality (`==` in
  /// Python). Two zones with equal `Some` keys compare equal. `None` (the
  /// default) means the zone is only equal to itself.
  fn eq_key(Self) -> String? = _
  /// Python `self.__eq__(other)` for zones whose equality is not a plain
  /// fingerprint match (e.g. it is not transitive). Return `None` for
  /// `NotImplemented`. Implementations typically inspect `other.eq_key()`.
  /// The default defers to `eq_key`.
  fn eq_with(Self, Tz) -> Bool? = _
}

///|
impl TzInfo with fn fromutc(_self, dt) {
  cpython_fromutc(dt)
}

///|
impl TzInfo with fn is_ambiguous(_self, _dt) {
  None
}

///|
impl TzInfo with fn eq_key(_self) {
  None
}

///|
impl TzInfo with fn eq_with(_self, _other) {
  None
}

///|
/// CPython's default `tzinfo.fromutc` algorithm.
pub fn cpython_fromutc(dt : DateTime) -> DateTime raise DateTimeError {
  guard dt.utcoffset() is Some(dtoff) else {
    raise ValueError("fromutc() requires a non-None utcoffset() result")
  }
  guard dt.dst() is Some(dtdst) else {
    raise ValueError("fromutc() requires a non-None dst() result")
  }
  let delta = dtoff - dtdst
  let dt = if delta.is_zero() { dt } else { dt.add(delta) }
  guard dt.dst() is Some(dtdst) else {
    raise ValueError(
      "fromutc(): dt.dst gave inconsistent results; cannot convert",
    )
  }
  dt.add(dtdst)
}

///|
let tz_counter : Ref[Int] = Ref(0)

///|
/// A time zone object: a `TzInfo` implementation plus a stable identity.
///
/// Python distinguishes zone identity (`a is b`, which governs datetime
/// comparison/subtraction semantics) from zone equality (`a == b`).
/// `Tz::is_same` is identity, `==` is value equality via `TzInfo::eq_key`.
/// Create a handle once and share it, like a Python object.
pub struct Tz {
  priv id : Int
  priv inner : &TzInfo
}

///|
/// Wrap a zone implementation in a fresh handle (a new "object").
pub fn Tz::new(inner : &TzInfo) -> Tz {
  tz_counter.val += 1
  { id: tz_counter.val, inner, }
}

///|
/// The underlying zone implementation.
pub fn Tz::inner(self : Tz) -> &TzInfo {
  self.inner
}

///|
/// Object identity (Python `is`).
pub fn Tz::is_same(self : Tz, other : Tz) -> Bool {
  self.id == other.id
}

///|
fn check_offset(name : String, off : TimeDelta?) -> TimeDelta? {
  if off is Some(o) &&
    (
      o.days < -1 ||
      o.days >= 1 ||
      (o.days == -1 && o.seconds == 0 && o.microseconds == 0)
    ) {
    abort(
      "offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24), not \{o.repr()} (from \{name})",
    )
  }
  off
}

///|
fn Tz::attach(self : Tz, dt : DateTime?) -> DateTime? {
  match dt {
    Some(d) if !(d.tzinfo is Some(t) && t.is_same(self)) =>
      Some(d.with_tzinfo(Some(self)))
    _ => dt
  }
}

///|
/// `tz.utcoffset(dt)`. Aborts if the zone returns an offset outside
/// ±24h (Python raises `ValueError`; that is a zone implementation bug).
pub fn Tz::utcoffset(self : Tz, dt : DateTime?) -> TimeDelta? {
  check_offset("utcoffset", self.inner.utcoffset(self.attach(dt)))
}

///|
/// `tz.dst(dt)`.
pub fn Tz::dst(self : Tz, dt : DateTime?) -> TimeDelta? {
  check_offset("dst", self.inner.dst(self.attach(dt)))
}

///|
/// `tz.tzname(dt)`.
pub fn Tz::tzname(self : Tz, dt : DateTime?) -> String? {
  self.inner.tzname(self.attach(dt))
}

///|
/// `tz.fromutc(dt)`: `dt.tzinfo` must be this very zone (identity), and
/// the result carries this zone.
pub fn Tz::fromutc(self : Tz, dt : DateTime) -> DateTime raise DateTimeError {
  guard dt.tzinfo is Some(t) && t.is_same(self) else {
    raise ValueError("dt.tzinfo is not self")
  }
  let r = self.inner.fromutc(dt)
  { ..r, tzinfo: Some(self), }
}

///|
/// dateutil's `is_ambiguous`, `None` if the zone does not support it.
pub fn Tz::is_ambiguous(self : Tz, dt : DateTime) -> Bool? {
  self.inner.is_ambiguous(dt.with_tzinfo(Some(self)))
}

///|
pub fn Tz::repr(self : Tz) -> String {
  self.inner.repr()
}

///|
pub fn Tz::eq_key(self : Tz) -> String? {
  self.inner.eq_key()
}

///|
/// Python `repr()`.
pub impl Show for Tz with fn output(self, logger) {
  logger.write_string(self.inner.repr())
}

///|
/// Zone value equality (Python `==`): identity, else `self.eq_with(other)`,
/// else the reflected `other.eq_with(self)`, else matching `eq_key`s.
pub impl Eq for Tz with fn equal(self, other) {
  if self.is_same(other) {
    return true
  }
  match self.inner.eq_with(other) {
    Some(r) => r
    None =>
      match other.inner.eq_with(self) {
        Some(r) => r
        None =>
          self.inner.eq_key() is Some(a) &&
          other.inner.eq_key() is Some(b) &&
          a == b
      }
  }
}

///|
/// Identity-based equality of optional zones (`a is b`).
pub fn same_tz(a : Tz?, b : Tz?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => x.is_same(y)
    _ => false
  }
}
