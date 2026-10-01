// Port of dateutil's `tz.tzical` / `_tzicalvtz` / `_tzicalvtzcomp`
// (tz/tz.py). It lives in its own package because it needs `rrule.rrulestr`,
// which itself depends on `parser` and `tz`.

///|
/// One STANDARD or DAYLIGHT component of a VTIMEZONE (`_tzicalvtzcomp`).
priv struct Comp {
  tzoffsetto : @datetime.TimeDelta
  tzoffsetdiff : @datetime.TimeDelta
  isdst : Bool
  tzname : String?
  rrule : @rrule.RruleBase
}

///|
/// A zone defined by a VTIMEZONE block (`_tzicalvtz`).
priv struct VtzZone {
  tzid : String
  comps : Array[Comp]
  // Small most-recently-used cache of `(naive dt, fold) -> component`,
  // as in dateutil (at most 10 entries).
  cachedate : Array[(@datetime.DateTime, Int)]
  cachecomp : Array[Comp]
}

///|
fn naive_key_eq(
  a : (@datetime.DateTime, Int),
  b : (@datetime.DateTime, Int),
) -> Bool {
  // naive datetimes compare by wall fields (fold ignored), plus fold
  a.0 == b.0 && a.1 == b.1
}

///|
fn VtzZone::find_compdt(
  _self : VtzZone,
  comp : Comp,
  dt : @datetime.DateTime,
) -> @datetime.DateTime? {
  let dt = if comp.tzoffsetdiff < @datetime.zero_timedelta && dt.fold == 1 {
    dt.sub(comp.tzoffsetdiff) catch {
      _ => return None
    }
  } else {
    dt
  }
  comp.rrule.before(dt, inc=true) catch {
    _ => None
  }
}

///|
fn VtzZone::find_comp(self : VtzZone, dt : @datetime.DateTime) -> Comp {
  if self.comps.length() == 1 {
    return self.comps[0]
  }
  let dt = dt.with_tzinfo(None)
  let key = (dt, dt.fold)
  for i, k in self.cachedate {
    if naive_key_eq(k, key) {
      return self.cachecomp[i]
    }
  }
  let mut lastcompdt : @datetime.DateTime? = None
  let mut lastcomp : Comp? = None
  for comp in self.comps {
    let compdt = self.find_compdt(comp, dt)
    if compdt is Some(c) {
      match lastcompdt {
        Some(l) if !(l < c) => ()
        _ => {
          lastcompdt = Some(c)
          lastcomp = Some(comp)
        }
      }
    }
  }
  let result = match lastcomp {
    Some(c) => c
    None =>
      // RFC says nothing about what to do when a given time is before the
      // first onset date. We'll look for the first standard component, or
      // the first component, if none is found. (dateutil has a bug here,
      // `comp[0]`, which raises TypeError; we use the first component.)
      match self.comps.search_by(c => !c.isdst) {
        Some(i) => self.comps[i]
        None => self.comps[0]
      }
  }
  self.cachedate.insert(0, key)
  self.cachecomp.insert(0, result)
  if self.cachedate.length() > 10 {
    let _ = self.cachedate.pop()
    let _ = self.cachecomp.pop()
  }
  result
}

///|
impl @datetime.TzInfo for VtzZone with fn utcoffset(self, dt) {
  match dt {
    None => None
    Some(dt) => Some(self.find_comp(dt).tzoffsetto)
  }
}

///|
impl @datetime.TzInfo for VtzZone with fn dst(self, dt) {
  let comp = match dt {
    Some(dt) => self.find_comp(dt)
    None =>
      // Python only succeeds here for single-component zones.
      if self.comps.length() == 1 {
        self.comps[0]
      } else {
        return None
      }
  }
  if comp.isdst {
    Some(comp.tzoffsetdiff)
  } else {
    Some(@datetime.zero_timedelta)
  }
}

///|
impl @datetime.TzInfo for VtzZone with fn tzname(self, dt) {
  match dt {
    Some(dt) => self.find_comp(dt).tzname
    None => if self.comps.length() == 1 { self.comps[0].tzname } else { None }
  }
}

///|
impl @datetime.TzInfo for VtzZone with fn fromutc(_self, dt) {
  @tz.tzinfo_fromutc(dt)
}

///|
impl @datetime.TzInfo for VtzZone with fn is_ambiguous(_self, dt) {
  match dt.tzinfo {
    Some(tz) => Some(@tz.tzinfo_is_ambiguous(tz, dt))
    None => None
  }
}

///|
impl @datetime.TzInfo for VtzZone with fn repr(self) {
  "<tzicalvtz \{@datetime.py_str_repr(self.tzid)}>"
}

///|
/// A parsed iCalendar file holding one or more `VTIMEZONE` definitions
/// (dateutil `tz.tzical`), as set out in RFC 5545 section 4.6.5.
pub struct TzIcal {
  priv name : String
  priv vtz : Map[String, @datetime.Tz]
}

///|
/// Parse iCalendar text. `name` plays the role of the file object's
/// `name` attribute in `repr()`. Raises `@datetime.ValueError` for
/// malformed input; errors from `@rrule.rrulestr` (for a component's
/// recurrence lines) propagate unchanged.
///
/// ```mbt check
/// test {
///   let ical = @tzical.TzIcal::from_string(
///     (
///       #|BEGIN:VTIMEZONE
///       #|TZID:US-Eastern
///       #|BEGIN:STANDARD
///       #|DTSTART:19671029T020000
///       #|RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10
///       #|TZOFFSETFROM:-0400
///       #|TZOFFSETTO:-0500
///       #|TZNAME:EST
///       #|END:STANDARD
///       #|BEGIN:DAYLIGHT
///       #|DTSTART:19870405T020000
///       #|RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=4
///       #|TZOFFSETFROM:-0500
///       #|TZOFFSETTO:-0400
///       #|TZNAME:EDT
///       #|END:DAYLIGHT
///       #|END:VTIMEZONE
///     ),
///   )
///   let est = ical.get().unwrap()
///   let summer = @datetime.DateTime::new(2003, 7, 1, tzinfo=est)
///   inspect(summer, content="2003-07-01 00:00:00-04:00")
///   debug_inspect(summer.tzname(), content="Some(\"EDT\")")
/// }
/// ```
pub fn TzIcal::from_string(
  s : String,
  name? : String = "<string>",
) -> TzIcal raise {
  let ical = { name, vtz: {}, }
  ical.parse_rfc(s)
  ical
}

///|
/// `tzical(filename)`: read and parse an iCalendar file (native and js
/// backends; on wasm this raises `IOError`).
pub fn TzIcal::from_file(path : String) -> TzIcal raise {
  let s = read_file_text(path)
  let ical = { name: path, vtz: {}, }
  ical.parse_rfc(s)
  ical
}

///|
/// The available zone ids, in definition order.
pub fn TzIcal::keys(self : TzIcal) -> Array[String] {
  self.vtz.keys().to_array()
}

///|
/// Retrieve a zone by `tzid`. Without `tzid`, returns the only zone and
/// raises `ValueError` if there are zero or several. Returns `None` for an
/// unknown `tzid`.
pub fn TzIcal::get(
  self : TzIcal,
  tzid? : String,
) -> @datetime.Tz? raise @datetime.DateTimeError {
  match tzid {
    Some(id) => self.vtz.get(id)
    None => {
      if self.vtz.length() == 0 {
        raise @datetime.ValueError("no timezones defined")
      } else if self.vtz.length() > 1 {
        raise @datetime.ValueError("more than one timezone available")
      }
      self.vtz.values().next()
    }
  }
}

///|
/// Python `repr(tzical)`, e.g. `tzical('StringIO(PST8PDT)')`.
pub fn TzIcal::repr(self : TzIcal) -> String {
  "tzical(\{@datetime.py_str_repr(self.name)})"
}

///|
pub impl Show for TzIcal with fn output(self, logger) {
  logger.write_string(self.repr())
}

///|
pub extend TzIcal with Show::{to_string, output}

///|
pub impl Debug for TzIcal with fn to_repr(self) {
  Repr(self.repr())
}

///|
fn value_error(msg : String) -> @datetime.DateTimeError {
  @datetime.ValueError(msg)
}

///|
/// Python `int()` on a short ASCII digit string (with optional sign and
/// surrounding whitespace, as `int()` accepts).
fn py_int(s : StringView) -> Int raise @datetime.DateTimeError {
  let t = py_strip(s.to_owned())
  let bad = () => {
    value_error(
      "invalid literal for int() with base 10: \{@datetime.py_str_repr(s.to_owned())}",
    )
  }
  if t.is_empty() {
    raise bad()
  }
  let (neg, digits) = match t.get_char(0) {
    Some('+') => (false, t.view(start_offset=1))
    Some('-') => (true, t.view(start_offset=1))
    _ => (false, t[:])
  }
  if digits.is_empty() {
    raise bad()
  }
  let mut n = 0
  let mut prev_underscore = true
  for c in digits {
    if c == '_' && !prev_underscore {
      prev_underscore = true
      continue
    }
    guard c >= '0' && c <= '9' else { raise bad() }
    prev_underscore = false
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  if prev_underscore {
    raise bad()
  }
  if neg {
    -n
  } else {
    n
  }
}

///|
/// `tzical._parse_offset`: `[+-]HHMM[SS]` to seconds.
fn parse_offset(s : String) -> Int raise @datetime.DateTimeError {
  let s = py_strip(s)
  if s.is_empty() {
    raise value_error("empty offset")
  }
  let (signal, s) = match s.get_char(0) {
    Some('+') => (1, s.view(start_offset=1).to_owned())
    Some('-') => (-1, s.view(start_offset=1).to_owned())
    _ => (1, s)
  }
  let n = s.length()
  if n == 4 {
    (py_int(s.view(end_offset=2)) * 3600 + py_int(s.view(start_offset=2)) * 60) *
    signal
  } else if n == 6 {
    (
      py_int(s.view(end_offset=2)) * 3600 +
      py_int(s.view(start_offset=2, end_offset=4)) * 60 +
      py_int(s.view(start_offset=4))
    ) *
    signal
  } else {
    raise value_error("invalid offset: " + s)
  }
}

///|
fn TzIcal::parse_rfc(self : TzIcal, s : String) -> Unit raise {
  let lines = py_splitlines(s)
  if lines.is_empty() {
    raise value_error("empty string")
  }
  // Unfold
  let mut i = 0
  while i < lines.length() {
    let line = py_rstrip(lines[i])
    if line.is_empty() {
      lines.remove(i) |> ignore
    } else if i > 0 && line.has_prefix(" ") {
      lines[i - 1] = lines[i - 1] + line.view(start_offset=1).to_owned()
      lines.remove(i) |> ignore
    } else {
      i += 1
    }
  }
  let mut tzid : String? = None
  let comps : Array[Comp] = []
  let mut invtz = false
  let mut comptype : String? = None
  let mut founddtstart = false
  let mut tzoffsetfrom : Int? = None
  let mut tzoffsetto : Int? = None
  let rrulelines : Array[String] = []
  let mut tzname : String? = None
  for line in lines {
    if line.is_empty() {
      continue
    }
    guard line.find(":") is Some(colon) else {
      raise value_error("not enough values to unpack (expected 2, got 1)")
    }
    let name = line.view(end_offset=colon).to_owned()
    let value = line.view(start_offset=colon + 1).to_owned()
    let parms = name.split(";").map(p => p.to_owned()).collect()
    let name = ascii_upper(parms[0])
    let parms = parms[1:].to_owned()
    if invtz {
      if name == "BEGIN" {
        if value != "STANDARD" && value != "DAYLIGHT" {
          raise value_error("unknown component: " + value)
        }
        comptype = Some(value)
        founddtstart = false
        tzoffsetfrom = None
        tzoffsetto = None
        rrulelines.clear()
        tzname = None
      } else if name == "END" {
        if value == "VTIMEZONE" {
          if comptype is Some(ct) {
            raise value_error("component not closed: " + ct)
          }
          guard tzid is Some(id) && !id.is_empty() else {
            raise value_error("mandatory TZID not found")
          }
          if comps.is_empty() {
            raise value_error("at least one component is needed")
          }
          // Process vtimezone
          self.vtz[id] = @datetime.Tz::new(VtzZone::{
            tzid: id,
            comps: comps.copy(),
            cachedate: [],
            cachecomp: [],
          })
          invtz = false
        } else if comptype is Some(ct) && value == ct {
          if !founddtstart {
            raise value_error("mandatory DTSTART not found")
          }
          guard tzoffsetfrom is Some(from) else {
            raise value_error("mandatory TZOFFSETFROM not found")
          }
          guard tzoffsetto is Some(to) else {
            raise value_error("mandatory TZOFFSETFROM not found")
          }
          // Process component
          let rr = @rrule.rrulestr(
            rrulelines.join("\n"),
            compatible=true,
            ignoretz=true,
            cache=true,
          )
          let from = @datetime.TimeDelta::new(seconds=from)
          let to = @datetime.TimeDelta::new(seconds=to)
          comps.push({
            tzoffsetto: to,
            tzoffsetdiff: to - from,
            isdst: ct == "DAYLIGHT",
            tzname,
            rrule: rr,
          })
          comptype = None
        } else {
          raise value_error("invalid component end: " + value)
        }
      } else if comptype is Some(_) {
        if name == "DTSTART" {
          // DTSTART in VTIMEZONE takes a subset of valid RRULE values
          // under RFC 5545.
          for parm in parms {
            if parm != "VALUE=DATE-TIME" {
              raise value_error(
                "Unsupported DTSTART param in VTIMEZONE: " + parm,
              )
            }
          }
          rrulelines.push(line)
          founddtstart = true
        } else if name is ("RRULE" | "RDATE" | "EXRULE" | "EXDATE") {
          rrulelines.push(line)
        } else if name == "TZOFFSETFROM" {
          if !parms.is_empty() {
            raise value_error("unsupported \{name} parm: \{parms[0]} ")
          }
          tzoffsetfrom = Some(parse_offset(value))
        } else if name == "TZOFFSETTO" {
          if !parms.is_empty() {
            raise value_error("unsupported TZOFFSETTO parm: " + parms[0])
          }
          tzoffsetto = Some(parse_offset(value))
        } else if name == "TZNAME" {
          if !parms.is_empty() {
            raise value_error("unsupported TZNAME parm: " + parms[0])
          }
          tzname = Some(value)
        } else if name == "COMMENT" {
          ()
        } else {
          raise value_error("unsupported property: " + name)
        }
      } else if name == "TZID" {
        if !parms.is_empty() {
          raise value_error("unsupported TZID parm: " + parms[0])
        }
        tzid = Some(value)
      } else if name is ("TZURL" | "LAST-MODIFIED" | "COMMENT") {
        ()
      } else {
        raise value_error("unsupported property: " + name)
      }
    } else if name == "BEGIN" && value == "VTIMEZONE" {
      tzid = None
      comps.clear()
      invtz = true
    }
  }
}
