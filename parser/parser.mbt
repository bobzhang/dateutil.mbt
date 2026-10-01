// dateutil `parser.parse` / `parser.parser`: the generic date/time string
// parser, plus building the resulting datetime.

///|
/// What a `tzinfos` entry (or callback) yields for a time zone name: the
/// Python values `None`, a `tzinfo`, a TZ string or an integer offset.
pub(all) enum TzInfoSpec {
  /// Python `None`: the result is naive.
  NoTz
  /// A zone object.
  Zone(@datetime.Tz)
  /// An offset east of UTC in seconds (becomes `tzoffset(name, seconds)`).
  Offset(Int)
  /// A POSIX-style TZ string (becomes `tzstr(s)`).
  TzString(String)
}

///|
/// dateutil's `tzinfos` argument: a mapping from time zone names to zones,
/// or a function of `(tzname, tzoffset)`.
///
/// Like Python, a `Callback` is consulted for every parse (even when the
/// string contains no zone; it then receives `(None, None)`), while a
/// `Table` is only consulted for names it contains.
pub(all) enum TzInfos {
  Table(Map[String, TzInfoSpec])
  Callback((String?, Int?) -> TzInfoSpec raise)
}

///|
/// dateutil `parser.parser`: a parser bound to a `ParserInfo`.
pub struct Parser {
  info : ParserInfo
}

///|
/// `parser(info=None)`.
pub fn Parser::new(info? : ParserInfo) -> Parser {
  let info = match info {
    Some(i) => i
    None => ParserInfo::new()
  }
  { info, }
}

///|
/// dateutil's `DEFAULTPARSER`, created on first use.
let default_parser : Ref[Parser?] = { val: None, }

///|
fn get_default_parser() -> Parser {
  match default_parser.val {
    Some(p) => p
    None => {
      let p = Parser::new()
      default_parser.val = Some(p)
      p
    }
  }
}

///|
/// Today at midnight (dateutil's default `default`).
fn default_default() -> @datetime.DateTime {
  let now = @datetime.DateTime::now()
  try! now.replace(hour=0, minute=0, second=0, microsecond=0)
}

///|
fn Parser::parse_impl(
  self : Parser,
  timestr : String,
  default : @datetime.DateTime?,
  ignoretz : Bool,
  tzinfos : TzInfos?,
  dayfirst : Bool?,
  yearfirst : Bool?,
  fuzzy : Bool,
  on_warning : ((UnknownTimezoneWarning) -> Unit)?,
) -> (@datetime.DateTime, Array[String]) raise {
  let default = match default {
    Some(d) => d
    None => default_default()
  }
  let fields = parse_fields(self.info, timestr, dayfirst, yearfirst, fuzzy) catch {
    // Python raises decimal.InvalidOperation (an ArithmeticError) here.
    DecimalInvalidOperation(msg) => raise @datetime.ValueError(msg)
    e => raise e
  }
  guard fields is Some((res, skipped_tokens)) else {
    raise ParserError("Unknown string format: %s", timestr)
  }
  if res.count() == 0 {
    raise ParserError("String does not contain a date: %s", timestr)
  }
  let ret = build_naive(res, default) catch {
    @datetime.ValueError(msg) => raise ParserError(msg + ": %s", timestr)
    e => raise e
  }
  let ret = if ignoretz {
    ret
  } else {
    self.build_tzaware(ret, res, tzinfos, on_warning)
  }
  (ret, skipped_tokens)
}

///|
/// `parser.parse(timestr, ...)`: parse a date/time string into a
/// `DateTime`.
///
/// * `default`: fields missing from `timestr` are taken from it (default:
///   today at midnight). If that yields a day past the end of the month,
///   the last day of the month is used.
/// * `ignoretz`: ignore zones in the string and return a naive datetime.
/// * `tzinfos`: extra zone names/aliases (ignored if `ignoretz`).
/// * `dayfirst` / `yearfirst`: resolve ambiguous numeric dates (default:
///   the `ParserInfo` settings).
/// * `fuzzy`: skip unknown tokens ("Today is January 1, 2047 at 8:21:00AM").
/// * `on_warning`: receives `UnknownTimezoneWarning`s (Python's
///   `warnings.warn`).
///
/// Raises `ParserError` for unknown formats or invalid dates,
/// `@datetime.OverflowError` for values beyond a C int, and whatever the
/// zone constructors raise (e.g. an out-of-range `tzoffset`).
///
/// See `Parser::parse_with_tokens` for Python's `fuzzy_with_tokens=True`.
pub fn Parser::parse(
  self : Parser,
  timestr : String,
  default? : @datetime.DateTime,
  ignoretz? : Bool = false,
  tzinfos? : TzInfos,
  dayfirst? : Bool,
  yearfirst? : Bool,
  fuzzy? : Bool = false,
  on_warning? : (UnknownTimezoneWarning) -> Unit,
) -> @datetime.DateTime raise {
  self.parse_impl(
    timestr, default, ignoretz, tzinfos, dayfirst, yearfirst, fuzzy, on_warning,
  ).0
}

///|
/// `parser.parse(timestr, fuzzy_with_tokens=True, ...)`: fuzzy parsing
/// that also returns the skipped portions of the string.
pub fn Parser::parse_with_tokens(
  self : Parser,
  timestr : String,
  default? : @datetime.DateTime,
  ignoretz? : Bool = false,
  tzinfos? : TzInfos,
  dayfirst? : Bool,
  yearfirst? : Bool,
  on_warning? : (UnknownTimezoneWarning) -> Unit,
) -> (@datetime.DateTime, Array[String]) raise {
  self.parse_impl(
    timestr, default, ignoretz, tzinfos, dayfirst, yearfirst, true, on_warning,
  )
}

///|
fn parser_for(parserinfo : ParserInfo?) -> Parser {
  match parserinfo {
    Some(info) => Parser::new(info~)
    None => get_default_parser()
  }
}

///|
/// dateutil `parser.parse(timestr, parserinfo=None, **kwargs)`; see
/// `Parser::parse` for the options.
///
/// ```mbt check
/// test {
///   let default = @datetime.DateTime::new(2003, 9, 25)
///   inspect(
///     @parser.parse("Thu Sep 25 10:36:28 2003"),
///     content="2003-09-25 10:36:28",
///   )
///   inspect(
///     @parser.parse("10h36m28.5s", default~),
///     content="2003-09-25 10:36:28.500000",
///   )
///   inspect(
///     @parser.parse("2003-09-25T10:49:41.5-03:00").repr(),
///     content="datetime.datetime(2003, 9, 25, 10, 49, 41, 500000, tzinfo=tzoffset(None, -10800))",
///   )
///   inspect(
///     @parser.parse("10-09-03", dayfirst=true),
///     content="2003-09-10 00:00:00",
///   )
/// }
/// ```
pub fn parse(
  timestr : String,
  parserinfo? : ParserInfo,
  default? : @datetime.DateTime,
  ignoretz? : Bool = false,
  tzinfos? : TzInfos,
  dayfirst? : Bool,
  yearfirst? : Bool,
  fuzzy? : Bool = false,
  on_warning? : (UnknownTimezoneWarning) -> Unit,
) -> @datetime.DateTime raise {
  parser_for(parserinfo).parse_impl(
    timestr, default, ignoretz, tzinfos, dayfirst, yearfirst, fuzzy, on_warning,
  ).0
}

///|
/// dateutil `parser.parse(timestr, fuzzy_with_tokens=True, ...)`.
///
/// ```mbt check
/// test {
///   let (dt, skipped) = @parser.parse_with_tokens(
///     "Today is January 1, 2047 at 8:21:00AM",
///   )
///   inspect(dt, content="2047-01-01 08:21:00")
///   debug_inspect(
///     skipped,
///     content=(
///       #|["Today is ", " ", " ", "at "]
///     ),
///   )
/// }
/// ```
pub fn parse_with_tokens(
  timestr : String,
  parserinfo? : ParserInfo,
  default? : @datetime.DateTime,
  ignoretz? : Bool = false,
  tzinfos? : TzInfos,
  dayfirst? : Bool,
  yearfirst? : Bool,
  on_warning? : (UnknownTimezoneWarning) -> Unit,
) -> (@datetime.DateTime, Array[String]) raise {
  parser_for(parserinfo).parse_impl(
    timestr, default, ignoretz, tzinfos, dayfirst, yearfirst, true, on_warning,
  )
}

///|
/// `parser._build_naive`
fn build_naive(
  res : ParseResult,
  default : @datetime.DateTime,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  let mut day = res.day
  if res.day is None {
    // If the default day exceeds the last day of the month, fall back
    // to the end of the month.
    let cyear = res.year.unwrap_or(default.year.to_int64())
    let cmonth = res.month.unwrap_or(default.month.to_int64())
    let cday = default.day.to_int64()
    let mdays = days_in_month64(cyear, cmonth).to_int64() catch {
      ParseFail(msg) => raise @datetime.ValueError(msg)
    }
    if cday > mdays {
      day = Some(mdays)
    }
  }
  // `datetime.replace` converts every argument to a C int first.
  fn c_int(v : Int64?) -> Int? raise @datetime.DateTimeError {
    match v {
      Some(v) => Some(to_c_int(v))
      None => None
    }
  }

  let year = c_int(res.year)
  let month = c_int(res.month)
  let day = c_int(day)
  let hour = c_int(res.hour)
  let minute = c_int(res.minute)
  let second = c_int(res.second)
  let microsecond = c_int(res.microsecond)
  let naive = default.replace(
    year?,
    month?,
    day?,
    hour?,
    minute?,
    second?,
    microsecond?,
  )
  match res.weekday {
    Some(wd) if res.day is None => {
      if wd > 6 {
        // Python: `relativedelta(weekday=7)` raises IndexError (only
        // reachable with a custom WEEKDAYS table of more than 7 entries).
        raise @datetime.ValueError("tuple index out of range")
      }
      // naive + relativedelta(weekday=wd): the next such weekday (or today).
      @relativedelta.RelativeDelta::new(weekday=@datetime.Weekday::new(wd)).add_to_datetime(
        naive,
      )
    }
    _ => naive
  }
}

///|
/// `parser._assign_tzname`
fn assign_tzname(
  dt : @datetime.DateTime,
  tzname : String?,
) -> @datetime.DateTime {
  if dt.tzname() != tzname {
    let new_dt = @tz.enfold(dt, fold=1)
    if new_dt.tzname() == tzname {
      return new_dt
    }
  }
  dt
}

///|
/// `parser._build_tzinfo`
fn build_tzinfo(
  tzinfos : TzInfos,
  tzname : String?,
  tzoffset : Int64?,
) -> @datetime.Tz? raise {
  let tzdata = match tzinfos {
    Callback(f) => {
      // Offsets beyond an Int (hundreds of hours) cannot be passed on; Python
      // would pass the big int. Report instead of silently clamping.
      let off = match tzoffset {
        Some(o) => Some(to_c_int(o))
        None => None
      }
      f(tzname, off)
    }
    Table(m) =>
      match tzname {
        Some(n) => m.get(n).unwrap_or(NoTz)
        None => NoTz
      }
  }
  // handle case where tzinfo is paased an options that returns None
  // eg tzinfos = {'BRST' : None}
  match tzdata {
    NoTz => None
    Zone(z) => Some(z)
    TzString(s) => Some(@tz.tzstr(s))
    Offset(secs) => Some(@tz.tzoffset(tzname, secs))
  }
}

///|
/// `parser._build_tzaware`
fn Parser::build_tzaware(
  self : Parser,
  naive : @datetime.DateTime,
  res : ParseResult,
  tzinfos : TzInfos?,
  on_warning : ((UnknownTimezoneWarning) -> Unit)?,
) -> @datetime.DateTime raise {
  let use_tzinfos = match tzinfos {
    Some(Callback(_)) => true
    Some(Table(m)) =>
      match res.tzname {
        Some(n) => m.contains(n)
        None => false
      }
    None => false
  }
  if use_tzinfos {
    let tzinfo = build_tzinfo(tzinfos.unwrap(), res.tzname, res.tzoffset)
    let aware = naive.with_tzinfo(tzinfo)
    return assign_tzname(aware, res.tzname)
  }
  if res.tzname is Some(name) && local_tznames().contains(name) {
    let aware = naive.with_tzinfo(Some(@tz.tzlocal()))
    // Handle ambiguous local datetime
    let aware = assign_tzname(aware, res.tzname)
    // This is mostly relevant for winter GMT zones parsed in the UK
    if aware.tzname() != res.tzname && self.info.utczone_list.contains(name) {
      return aware.with_tzinfo(Some(@tz.utc))
    }
    return aware
  }
  match res.tzoffset {
    Some(0L) => naive.with_tzinfo(Some(@tz.utc))
    Some(off) =>
      naive.with_tzinfo(Some(@tz.tzoffset(res.tzname, to_c_int(off))))
    None =>
      match res.tzname {
        None =>
          // i.e. no timezone information was found.
          naive
        Some(name) => {
          // tz-like string was parsed but we don't know what to do
          // with it
          if on_warning is Some(f) {
            f({ tzname: name, })
          }
          naive
        }
      }
  }
}

///|
/// Python `time.tzname`.
fn local_tznames() -> Array[String] {
  let (std, dst) = @datetime.local_zone().tzname
  [std, dst]
}
