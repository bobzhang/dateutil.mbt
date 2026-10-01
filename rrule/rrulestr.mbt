// `rrulestr` (Python `_rrulestr`): parse RFC 5545 recurrence strings.

///|
/// Either a single rule or a set — what `rrulestr` returns (Python returns
/// an `rrule` or an `rruleset`, both `rrulebase` instances).
pub(all) enum RruleBase {
  Rule(Rrule)
  Set(RruleSet)
}

///|
/// How `rrulestr` resolves `TZID=` parameters (Python `tzids`).
pub(all) enum TzIds {
  /// Python mapping: `tzids.get(name)`; unknown names give no zone.
  Mapping(Map[String, @datetime.Tz])
  /// Python callable: `tzids(name)`; `None` gives no zone. Errors propagate.
  Lookup((String) -> @datetime.Tz? raise)
}

///|
/// Parse a recurrence string (Python `rrulestr(s, **kwargs)`).
///
/// * `dtstart`: default start if the string has no `DTSTART`.
/// * `cache`: enable caching on the result.
/// * `unfold`: join RFC 5545 folded lines (continuations start with a space).
/// * `forceset`: always return a `Set`.
/// * `compatible`: implies `unfold` and `forceset`, and adds `DTSTART` as an
///   `RDATE`.
/// * `ignoretz`: drop time zones from parsed date values.
/// * `tzids`: resolve `TZID=` parameters (default: `tz.gettz`).
///
/// Raises `ValueError` (as `@datetime.DateTimeError`) for malformed input,
/// and propagates errors raised by a `tzids` callback.
///
/// ```mbt check
/// test {
///   let rr = @rrule.rrulestr(
///     "DTSTART:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=3;BYDAY=1TU,-1TH",
///   )
///   inspect(
///     rr.to_array().map(d => d.isoformat()).join(" "),
///     content="1997-12-25T09:00:00 1998-01-06T09:00:00 1998-12-31T09:00:00",
///   )
/// }
/// ```
pub fn rrulestr(
  s : String,
  dtstart? : @datetime.DateTime,
  cache? : Bool = false,
  unfold? : Bool = false,
  forceset? : Bool = false,
  compatible? : Bool = false,
  ignoretz? : Bool = false,
  tzids? : TzIds,
) -> RruleBase raise {
  let (forceset, unfold) = if compatible {
    (true, true)
  } else {
    (forceset, unfold)
  }
  let tzid_names = find_tzid_names(s)
  let s = py_upper(s)
  if py_strip(s) == "" {
    raise @datetime.ValueError("empty string")
  }
  let lines = if unfold { unfold_lines(s) } else { py_split_ws(s) }
  if !forceset &&
    lines.length() == 1 &&
    (s.find(":") is None || s.has_prefix("RRULE:")) {
    return Rule(parse_rfc_rrule(lines[0], dtstart, cache, ignoretz))
  }
  let rrulevals = []
  let rdatevals = []
  let exrulevals = []
  let exdatevals = []
  let mut dtstart = dtstart
  for line in lines {
    if line == "" {
      continue
    }
    let (name, value) = match line.find(":") {
      None => ("RRULE", line)
      Some(i) =>
        (
          line.unsafe_substring(start=0, end=i),
          line.unsafe_substring(start=i + 1, end=line.length()),
        )
    }
    let parms = name.split(";").map(x => x.to_owned()).to_array()
    let name = parms[0]
    let parms = parms[1:].to_owned()
    match name {
      "RRULE" => {
        for parm in parms {
          raise @datetime.ValueError("unsupported RRULE parm: " + parm)
        }
        rrulevals.push(value)
      }
      "RDATE" => {
        for parm in parms {
          if parm != "VALUE=DATE-TIME" {
            raise @datetime.ValueError("unsupported RDATE parm: " + parm)
          }
        }
        rdatevals.push(value)
      }
      "EXRULE" => {
        for parm in parms {
          raise @datetime.ValueError("unsupported EXRULE parm: " + parm)
        }
        exrulevals.push(value)
      }
      "EXDATE" =>
        exdatevals.append(
          parse_date_value(value, parms, tzid_names, ignoretz, tzids),
        )
      "DTSTART" => {
        let dtvals = parse_date_value(value, parms, tzid_names, ignoretz, tzids)
        if dtvals.length() != 1 {
          raise @datetime.ValueError(
            "Multiple DTSTART values specified:" + value,
          )
        }
        dtstart = Some(dtvals[0])
      }
      _ => raise @datetime.ValueError("unsupported property: " + name)
    }
  }
  if forceset ||
    rrulevals.length() > 1 ||
    !rdatevals.is_empty() ||
    !exrulevals.is_empty() ||
    !exdatevals.is_empty() {
    let rset = RruleSet::new(cache~)
    for value in rrulevals {
      rset.rrule(parse_rfc_rrule(value, dtstart, false, ignoretz))
    }
    for value in rdatevals {
      for datestr in value.split(",") {
        rset.rdate(parse_datetime(datestr.to_owned(), ignoretz))
      }
    }
    for value in exrulevals {
      rset.exrule(parse_rfc_rrule(value, dtstart, false, ignoretz))
    }
    for value in exdatevals {
      rset.exdate(value)
    }
    if compatible && dtstart is Some(d) {
      rset.rdate(d)
    }
    Set(rset)
  } else {
    guard rrulevals is [first, ..] else { raise index_error() }
    Rule(parse_rfc_rrule(first, dtstart, cache, ignoretz))
  }
}

///|
/// Python `dict(map(lambda x: (x.upper(), x), re.findall('TZID=(?P<name>[^:]+):', s)))`.
fn find_tzid_names(s : String) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  let n = s.length()
  let mut i = 0
  while i < n {
    if s.unsafe_substring(start=i, end=n).has_prefix("TZID=") {
      let j = i + 5
      let mut k = j
      while k < n && s[k] != ':' {
        k += 1
      }
      if k > j && k < n {
        let name = s.unsafe_substring(start=j, end=k)
        names[py_upper(name)] = name
        i = k + 1
        continue
      }
    }
    i += 1
  }
  names
}

///|
/// The `unfold=True` line splitting of `_parse_rfc`.
fn unfold_lines(s : String) -> Array[String] {
  let lines = py_splitlines(s)
  let mut i = 0
  while i < lines.length() {
    let line = py_rstrip(lines[i])
    if line == "" {
      lines.remove(i) |> ignore
    } else if i > 0 && line.has_prefix(" ") {
      lines[i - 1] = lines[i - 1] +
        line.unsafe_substring(start=1, end=line.length())
      lines.remove(i) |> ignore
    } else {
      i += 1
    }
  }
  lines
}

///|
/// Python `_parse_date_value`: DTSTART/EXDATE values with `TZID`/`VALUE`
/// parameters.
fn parse_date_value(
  date_value : String,
  parms : Array[String],
  rule_tzids : Map[String, String],
  ignoretz : Bool,
  tzids : TzIds?,
) -> Array[@datetime.DateTime] raise {
  let mut tzid : @datetime.Tz? = None
  let mut value_found = false
  for parm in parms {
    if parm.has_prefix("TZID=") {
      let pieces = split_all(parm, "TZID=")
      guard rule_tzids.get(pieces[pieces.length() - 1]) is Some(tzkey) else {
        continue
      }
      tzid = match tzids {
        None => default_gettz(tzkey)
        Some(Lookup(f)) => f(tzkey)
        Some(Mapping(m)) => m.get(tzkey)
      }
      continue
    }
    // RFC 5545 3.8.2.4: The VALUE parameter is optional, but may be found
    // only once.
    if parm != "VALUE=DATE-TIME" && parm != "VALUE=DATE" {
      raise @datetime.ValueError("unsupported parm: " + parm)
    } else {
      if value_found {
        raise @datetime.ValueError(
          "Duplicate value parameter found in: " + parm,
        )
      }
      value_found = true
    }
  }
  let datevals = []
  for datestr in split_all(date_value, ",") {
    let mut date = parse_datetime(datestr, ignoretz)
    if tzid is Some(tz) {
      if date.tzinfo is None {
        date = date.with_tzinfo(Some(tz))
      } else {
        raise @datetime.ValueError("DTSTART/EXDATE specifies multiple timezone")
      }
    }
    datevals.push(date)
  }
  datevals
}

///|
/// Python `_parse_rfc_rrule`: one `RRULE`/`EXRULE` value.
fn parse_rfc_rrule(
  line : String,
  dtstart : @datetime.DateTime?,
  cache : Bool,
  ignoretz : Bool,
) -> Rrule raise @datetime.DateTimeError {
  let value = if line.find(":") is Some(_) {
    guard split_all(line, ":") is [name, value] else {
      raise @datetime.ValueError("too many values to unpack (expected 2)")
    }
    if name != "RRULE" {
      raise @datetime.ValueError("unknown parameter name")
    }
    value
  } else {
    line
  }
  let kw = RruleKwargs::new()
  for pair in split_all(value, ";") {
    guard split_all(pair, "=") is [name, value] else {
      raise @datetime.ValueError(
        "not enough values to unpack (expected 2) in: " + pair,
      )
    }
    let name = py_upper(name)
    let value = py_upper(value)
    kw.handle(name, value, ignoretz) catch {
      UnknownParameter =>
        raise @datetime.ValueError("unknown parameter '\{name}'")
      _ => raise @datetime.ValueError("invalid '\{name}': \{value}")
    }
  }
  guard kw.freq is Some(freq) else {
    raise @datetime.TypeError(
      "__init__() missing 1 required positional argument: 'freq'",
    )
  }
  Rrule::new(
    freq,
    dtstart?,
    interval?=kw.interval,
    wkst?=kw.wkst,
    count?=kw.count,
    until?=kw.until,
    bysetpos?=kw.bysetpos,
    bymonth?=kw.bymonth,
    bymonthday?=kw.bymonthday,
    byyearday?=kw.byyearday,
    byeaster?=kw.byeaster,
    byweekno?=kw.byweekno,
    byweekday?=kw.byweekday,
    byhour?=kw.byhour,
    byminute?=kw.byminute,
    bysecond?=kw.bysecond,
    cache~,
  )
}

///|
/// The keyword arguments collected from an RRULE value (Python `rrkwargs`).
priv struct RruleKwargs {
  mut freq : Freq?
  mut interval : Int?
  mut count : Int?
  mut until : @datetime.DateTime?
  mut wkst : Weekday?
  mut bysetpos : Array[Int]?
  mut bymonth : Array[Int]?
  mut bymonthday : Array[Int]?
  mut byyearday : Array[Int]?
  mut byeaster : Array[Int]?
  mut byweekno : Array[Int]?
  mut byweekday : Array[Weekday]?
  mut byhour : Array[Int]?
  mut byminute : Array[Int]?
  mut bysecond : Array[Int]?
}

///|
fn RruleKwargs::new() -> RruleKwargs {
  {
    freq: None,
    interval: None,
    count: None,
    until: None,
    wkst: None,
    bysetpos: None,
    bymonth: None,
    bymonthday: None,
    byyearday: None,
    byeaster: None,
    byweekno: None,
    byweekday: None,
    byhour: None,
    byminute: None,
    bysecond: None,
  }
}

///|
priv suberror HandleError {
  /// Python `AttributeError` (no `_handle_<NAME>` method).
  UnknownParameter
  /// Python `KeyError`/`ValueError` inside a handler.
  InvalidValue
}

///|
fn int_list(value : String) -> Array[Int] raise HandleError {
  split_all(value, ",").map(x => py_int(x))
}

///|
/// Python `_handle_<NAME>(rrkwargs, name, value)`.
fn RruleKwargs::handle(
  self : RruleKwargs,
  name : String,
  value : String,
  ignoretz : Bool,
) -> Unit raise HandleError {
  match name {
    "INTERVAL" => self.interval = Some(py_int(value))
    "COUNT" => self.count = Some(py_int(value))
    "BYSETPOS" => self.bysetpos = Some(int_list(value))
    "BYMONTH" => self.bymonth = Some(int_list(value))
    "BYMONTHDAY" => self.bymonthday = Some(int_list(value))
    "BYYEARDAY" => self.byyearday = Some(int_list(value))
    "BYEASTER" => self.byeaster = Some(int_list(value))
    "BYWEEKNO" => self.byweekno = Some(int_list(value))
    "BYHOUR" => self.byhour = Some(int_list(value))
    "BYMINUTE" => self.byminute = Some(int_list(value))
    "BYSECOND" => self.bysecond = Some(int_list(value))
    "FREQ" =>
      self.freq = match Freq::from_name(value) {
        Some(f) => Some(f)
        None => raise InvalidValue
      }
    "UNTIL" =>
      self.until = Some(
        parse_datetime(value, ignoretz) catch {
          _ => raise InvalidValue
        },
      )
    "WKST" => self.wkst = Some(weekdays[weekday_index(value)])
    "BYWEEKDAY" | "BYDAY" => self.byweekday = Some(parse_byday(value))
    _ => raise UnknownParameter
  }
}

///|
/// Python `_weekday_map[w]`.
fn weekday_index(w : String) -> Int raise HandleError {
  match w {
    "MO" => 0
    "TU" => 1
    "WE" => 2
    "TH" => 3
    "FR" => 4
    "SA" => 5
    "SU" => 6
    _ => raise InvalidValue
  }
}

///|
/// Python `_handle_BYWEEKDAY`: `+1MO` or `MO(+1)` items.
fn parse_byday(value : String) -> Array[Weekday] raise HandleError {
  let l = []
  for wday in split_all(value, ",") {
    let (w, n) = if wday.find("(") is Some(_) {
      // If it's of the form TH(+1), etc.
      let splt = split_all(wday, "(")
      let inner = splt[1]
      if inner.length() == 0 {
        raise InvalidValue
      }
      (
        splt[0],
        Some(py_int(inner.unsafe_substring(start=0, end=inner.length() - 1))),
      )
    } else if wday.length() > 0 {
      // If it's of the form +1MO
      let mut i = 0
      while i < wday.length() {
        let c = wday[i]
        if !(c == '+' || c == '-' || (c >= '0' && c <= '9')) {
          break
        }
        if i == wday.length() - 1 {
          break
        }
        i += 1
      }
      let n = wday.unsafe_substring(start=0, end=i)
      let w = wday.unsafe_substring(start=i, end=wday.length())
      (w, if n == "" { None } else { Some(py_int(n)) })
    } else {
      raise InvalidValue // "Invalid (empty) BYDAY specification."
    }
    let base = weekdays[weekday_index(w)]
    l.push(
      match n {
        None => base.nth(None)
        Some(n) => nth(base, n) catch { _ => raise InvalidValue }
      },
    )
  }
  l
}

///|
/// Python `s.split(sep)` (all pieces, as owned strings).
fn split_all(s : String, sep : String) -> Array[String] {
  s.split(sep).map(x => x.to_owned()).to_array()
}
