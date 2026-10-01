// dateutil `tzrangebase`, `tzrange` and `tzstr`: zones with one annual
// transition into and one out of DST.

///|
priv struct TzRange {
  std_abbr : String?
  dst_abbr : String?
  std_offset : @datetime.TimeDelta
  dst_offset : @datetime.TimeDelta
  start_delta : TzRangeDelta?
  end_delta : TzRangeDelta?
  hasdst : Bool
  /// `tzstr`'s source string (`None` for a plain `tzrange`); only used by
  /// `repr()`.
  source : String?
}

///|
fn TzRange::dst_base_offset(self : TzRange) -> @datetime.TimeDelta {
  self.dst_offset - self.std_offset
}

///|
/// `tzrange.transitions(year)`: the DST on and off transitions, both in
/// standard time; `None` for zones without DST. (Also `None` where Python
/// raises: no end rule, or a transition outside the datetime range.)
fn TzRange::transitions(
  self : TzRange,
  year : Int,
) -> (@datetime.DateTime, @datetime.DateTime)? {
  if !self.hasdst {
    return None
  }
  guard self.start_delta is Some(start) && self.end_delta is Some(end) else {
    return None
  }
  let base_year = @datetime.DateTime::new(year, 1, 1) catch {
    _ => return None
  }
  let start = start.add_to_datetime(base_year) catch { _ => return None }
  let end = end.add_to_datetime(base_year) catch { _ => return None }
  Some((start, end))
}

///|
/// `tzrangebase._naive_isdst`.
fn naive_isdst(
  dt : @datetime.DateTime,
  transitions : (@datetime.DateTime, @datetime.DateTime),
) -> Bool {
  let (dston, dstoff) = transitions
  let dt = dt.with_tzinfo(None)
  if dston < dstoff {
    dston <= dt && dt < dstoff
  } else {
    !(dstoff <= dt && dt < dston)
  }
}

///|
/// `tzrangebase.is_ambiguous`.
fn TzRange::is_ambiguous_naive(self : TzRange, dt : @datetime.DateTime) -> Bool {
  if !self.hasdst {
    return false
  }
  guard self.transitions(dt.year) is Some((_, end)) else { return false }
  let dt = dt.with_tzinfo(None)
  let end_plus = end.add(self.dst_base_offset()) catch { _ => return false }
  end <= dt && dt < end_plus
}

///|
/// `tzrangebase._isdst`; `None` for a `time` query in a zone with DST.
fn TzRange::isdst(self : TzRange, dt : @datetime.DateTime?) -> Bool? {
  if !self.hasdst {
    return Some(false)
  }
  guard dt is Some(dt) else { return None }
  guard self.transitions(dt.year) is Some(transitions) else {
    return Some(false)
  }
  let dt = dt.with_tzinfo(None)
  let isdst = naive_isdst(dt, transitions)
  // Handle ambiguous dates
  if !isdst && self.is_ambiguous_naive(dt) {
    Some(dt.fold == 0)
  } else {
    Some(isdst)
  }
}

///|
impl @datetime.TzInfo for TzRange with fn utcoffset(self, dt) {
  match self.isdst(dt) {
    None => None
    Some(true) => Some(self.dst_offset)
    Some(false) => Some(self.std_offset)
  }
}

///|
impl @datetime.TzInfo for TzRange with fn dst(self, dt) {
  match self.isdst(dt) {
    None => None
    Some(true) => Some(self.dst_base_offset())
    Some(false) => Some(@datetime.zero_timedelta)
  }
}

///|
impl @datetime.TzInfo for TzRange with fn tzname(self, dt) {
  if self.isdst(dt) is Some(true) {
    self.dst_abbr
  } else {
    self.std_abbr
  }
}

///|
/// `tzrangebase.fromutc`: computed from the UTC transitions of the year.
impl @datetime.TzInfo for TzRange with fn fromutc(self, dt) {
  // Get transitions - if there are none, fixed offset
  guard self.transitions(dt.year) is Some((dston, dstoff)) else {
    let off = match self.isdst(Some(dt)) {
      Some(true) => self.dst_offset
      _ => self.std_offset
    }
    return dt.add(off)
  }
  // Get the transition times in UTC
  let utc_transitions = (dston.sub(self.std_offset), dstoff.sub(self.std_offset))
  let dt_utc = dt.with_tzinfo(None)
  let isdst = naive_isdst(dt_utc, utc_transitions)
  let dt_wall = if isdst {
    dt.add(self.dst_offset)
  } else {
    dt.add(self.std_offset)
  }
  let fold = !isdst && self.is_ambiguous_naive(dt_wall)
  enfold(dt_wall, fold=if fold { 1 } else { 0 })
}

///|
impl @datetime.TzInfo for TzRange with fn is_ambiguous(self, dt) {
  Some(self.is_ambiguous_naive(dt))
}

///|
impl @datetime.TzInfo for TzRange with fn repr(self) {
  match self.source {
    None => "tzrange(...)"
    Some(s) => "tzstr(\{@datetime.py_str_repr(s)})"
  }
}

///|
/// `tzrange.__eq__`: abbreviations, offsets and transition rules (`tzstr`
/// is a `tzrange` subclass and compares the same way).
impl @datetime.TzInfo for TzRange with fn eq_key(self) {
  fn opt_str(s : String?) -> String {
    match s {
      None => "None"
      Some(s) => @datetime.py_str_repr(s)
    }
  }

  fn opt_delta(d : TzRangeDelta?) -> String {
    match d {
      None => "None"
      Some(d) => d.fingerprint()
    }
  }

  Some(
    "dateutil.tzrange:\{opt_str(self.std_abbr)},\{opt_str(self.dst_abbr)},\{self.std_offset.repr()},\{self.dst_offset.repr()},\{opt_delta(self.start_delta)},\{opt_delta(self.end_delta)}",
  )
}

///|
/// The default DST start: 2AM on the first Sunday in April.
fn default_start_delta() -> TzRangeDelta {
  TzRangeDelta::new(hours=2, month=4, day=1, weekday=@datetime.su.nth(Some(1))) catch {
    _ => panic()
  }
}

///|
/// The default DST end: 1AM standard time (2AM DST) on the last Sunday in
/// October.
fn default_end_delta() -> TzRangeDelta {
  TzRangeDelta::new(
    hours=1,
    month=10,
    day=31,
    weekday=@datetime.su.nth(Some(-1)),
  ) catch {
    _ => panic()
  }
}

///|
fn TzRange::new(
  stdabbr : String?,
  stdoffset : @datetime.TimeDelta?,
  dstabbr : String?,
  dstoffset : @datetime.TimeDelta?,
  start : TzRangeDelta?,
  end : TzRangeDelta?,
  defaults~ : Bool,
) -> TzRange {
  let has_dstabbr = dstabbr is Some(a) && a != ""
  let std_offset = stdoffset.unwrap_or(@datetime.zero_timedelta)
  let dst_offset = match dstoffset {
    Some(d) => d
    None =>
      if has_dstabbr && stdoffset is Some(_) {
        std_offset + @datetime.TimeDelta::new(hours=1)
      } else {
        @datetime.zero_timedelta
      }
  }
  let start_delta = if defaults && has_dstabbr && start is None {
    Some(default_start_delta())
  } else {
    start
  }
  let end_delta = if defaults && has_dstabbr && end is None {
    Some(default_end_delta())
  } else {
    end
  }
  {
    std_abbr: stdabbr,
    dst_abbr: dstabbr,
    std_offset,
    dst_offset,
    start_delta,
    end_delta,
    hasdst: start_delta is Some(s) && s.to_bool(),
    source: None,
  }
}

///|
/// `tzrange(stdabbr, stdoffset, dstabbr, dstoffset, start, end)`: a zone
/// given by its offsets, abbreviations and DST rules.
///
/// * `stdoffset` defaults to UTC (zero).
/// * With a `dstabbr` and no other DST information, DST is one hour ahead
///   of standard time and runs from 2AM on the first Sunday in April to
///   2AM (DST) on the last Sunday in October.
/// * `start`/`end` are relative deltas from January 1st of the year; `end`
///   is expressed in *standard* time.
///
/// Note: `start`/`end` currently take the stand-in `TzRangeDelta`; they
/// will take `@relativedelta.RelativeDelta` once that package lands.
///
/// ```mbt check
/// test {
///   let est = @tz.tzrange(
///     Some("EST"),
///     stdoffset=@datetime.TimeDelta::new(hours=-5),
///     dstabbr="EDT",
///   )
///   assert_true(est == @tz.tzstr("EST5EDT"))
///   let dt = @datetime.DateTime::new(2003, 7, 1, tzinfo=est)
///   debug_inspect(dt.tzname(), content="Some(\"EDT\")")
///   inspect(est, content="tzrange(...)")
/// }
/// ```
pub fn tzrange(
  stdabbr : String?,
  stdoffset? : @datetime.TimeDelta,
  dstabbr? : String,
  dstoffset? : @datetime.TimeDelta,
  start? : TzRangeDelta,
  end? : TzRangeDelta,
) -> @datetime.Tz {
  @datetime.Tz::new(
    TzRange::new(
      stdabbr,
      stdoffset,
      dstabbr,
      dstoffset,
      start,
      end,
      defaults=true,
    ),
  )
}

///|
/// `tzstr._delta`: the relativedelta for a parsed transition rule.
fn tzstr_delta(
  x : TzRule,
  isend : Bool,
  std_offset : @datetime.TimeDelta,
  dst_offset : @datetime.TimeDelta,
) -> TzRangeDelta raise @datetime.DateTimeError {
  let mut month : Int? = None
  let mut day : Int? = None
  let mut weekday : @datetime.Weekday? = None
  let mut yearday : Int? = None
  let mut nlyearday : Int? = None
  if x.month is Some(m) {
    month = Some(m)
    if x.weekday is Some(wd) {
      let week = x.week.unwrap_or(0)
      weekday = Some(@datetime.Weekday::new(wd, n=week))
      day = Some(if week > 0 { 1 } else { 31 })
    } else if x.day is Some(d) && d != 0 {
      day = Some(d)
    }
  } else if x.yday is Some(y) {
    yearday = Some(y)
  } else if x.jyday is Some(j) {
    nlyearday = Some(j)
  }
  if month is None && yearday is None && nlyearday is None {
    // Default is to start on first sunday of april, and end on last
    // sunday of october.
    if !isend {
      month = Some(4)
      day = Some(1)
      weekday = Some(@datetime.su.nth(Some(1)))
    } else {
      month = Some(10)
      day = Some(31)
      weekday = Some(@datetime.su.nth(Some(-1)))
    }
  }
  // Default is 2AM.
  let mut seconds = x.time.unwrap_or(7200)
  if isend {
    // Convert to standard time, to follow the documented way of working
    // with the extra hour.
    let delta = dst_offset - std_offset
    seconds -= delta.seconds + delta.days * 86400
  }
  TzRangeDelta::new(month?, day?, weekday?, yearday?, nlyearday?, seconds~)
}

///|
fn TzRange::from_tzstr(
  s : String,
  posix_offset : Bool,
) -> TzRange raise @datetime.DateTimeError {
  guard parse_tzstr(s) is Some(res) && !res.any_unused_tokens else {
    raise @datetime.ValueError("unknown string format")
  }
  // Here we break the compatibility with the TZ variable handling.
  // GMT-3 actually *means* the timezone -3.
  if res.stdabbr is Some("GMT" | "UTC") && !posix_offset {
    guard res.stdoffset is Some(o) else {
      raise @datetime.TypeError(
        "unsupported operand type(s) for *=: 'NoneType' and 'int'",
      )
    }
    res.stdoffset = Some(-o)
  }
  let to_delta = (o : Int?) => o.map(s => @datetime.TimeDelta::new(seconds=s))
  let base = TzRange::new(
    res.stdabbr,
    to_delta(res.stdoffset),
    res.dstabbr,
    to_delta(res.dstoffset),
    None,
    None,
    defaults=false,
  )
  let (start_delta, end_delta) = if res.dstabbr is (None | Some("")) {
    (None, None)
  } else {
    let start = tzstr_delta(res.start, false, base.std_offset, base.dst_offset)
    let end = if start.to_bool() {
      Some(tzstr_delta(res.end, true, base.std_offset, base.dst_offset))
    } else {
      None
    }
    (Some(start), end)
  }
  {
    ..base,
    start_delta,
    end_delta,
    hasdst: start_delta is Some(d) && d.to_bool(),
    source: Some(s),
  }
}

///|
let tzstr_cache : Map[(String, Bool), @datetime.Tz] = Map([])

///|
/// `tzstr.instance(s, posix_offset)`: a fresh, uncached zone.
pub fn tzstr_instance(
  s : String,
  posix_offset? : Bool = false,
) -> @datetime.Tz raise @datetime.DateTimeError {
  @datetime.Tz::new(TzRange::from_tzstr(s, posix_offset))
}

///|
/// `tzstr(s, posix_offset)`: a zone from a POSIX/GNU `TZ` string such as
/// `EST5EDT,M3.2.0/2,M11.1.0/2` (or dateutil's legacy
/// `EST5EDT,4,1,0,7200,10,-1,0,7200,3600` form). Unlike POSIX, `GMT+3`
/// and `UTC+3` mean 3 hours *ahead* of UTC unless `posix_offset` is set.
/// Raises `ValueError` for strings it cannot parse. Equal arguments return
/// the same (cached) zone.
///
/// ```mbt check
/// test {
///   let tz = @tz.tzstr("AEST-10AEDT,M10.1.0/2,M4.1.0/3")
///   inspect(tz, content="tzstr('AEST-10AEDT,M10.1.0/2,M4.1.0/3')")
///   let dt = @datetime.DateTime::new(2012, 1, 1, tzinfo=tz)
///   inspect(dt, content="2012-01-01 00:00:00+11:00")
///   assert_true(@tz.tzstr("AEST-10AEDT,M10.1.0/2,M4.1.0/3").is_same(tz))
/// }
/// ```
pub fn tzstr(
  s : String,
  posix_offset? : Bool = false,
) -> @datetime.Tz raise @datetime.DateTimeError {
  let key = (s, posix_offset)
  match tzstr_cache.get(key) {
    Some(tz) => tz
    None => {
      let tz = tzstr_instance(s, posix_offset~)
      tzstr_cache[key] = tz
      tz
    }
  }
}
