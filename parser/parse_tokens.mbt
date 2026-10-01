// dateutil `parser._parse` and its token handlers: turns the token list into
// a `_result` (the parsed fields, before building a datetime).

///|
/// dateutil `parser._result`.
priv struct ParseResult {
  mut year : Int64?
  mut month : Int64?
  mut day : Int64?
  mut weekday : Int?
  mut hour : Int64?
  mut minute : Int64?
  mut second : Int64?
  mut microsecond : Int64?
  mut tzname : String?
  mut tzoffset : Int64?
  mut ampm : Int?
  mut century_specified : Bool
}

///|
fn ParseResult::new() -> ParseResult {
  {
    year: None,
    month: None,
    day: None,
    weekday: None,
    hour: None,
    minute: None,
    second: None,
    microsecond: None,
    tzname: None,
    tzoffset: None,
    ampm: None,
    century_specified: false,
  }
}

///|
/// `len(res)`: the number of attributes that are not `None`.
fn ParseResult::count(self : ParseResult) -> Int {
  let flags = [
    self.year is Some(_),
    self.month is Some(_),
    self.day is Some(_),
    self.weekday is Some(_),
    self.hour is Some(_),
    self.minute is Some(_),
    self.second is Some(_),
    self.microsecond is Some(_),
    self.tzname is Some(_),
    self.tzoffset is Some(_),
    self.ampm is Some(_),
  ]
  flags.fold(init=0, (n, f) => if f { n + 1 } else { n })
}

///|
/// `tokens[i]`, raising like Python's `IndexError` when out of range.
fn tok(tokens : Array[String], i : Int) -> String raise ParseFail {
  match tokens.get(i) {
    Some(t) => t
    None => raise ParseFail("list index out of range")
  }
}

///|
/// Python `int(s)` inside `_parse` (failures abort the parse).
fn pint(s : String) -> Int64 raise ParseFail {
  py_int(s) catch {
    e => raise ParseFail(e.to_string())
  }
}

///|
/// `parser._parsems`: parse an `I[.F]` seconds value into
/// (seconds, microseconds).
fn parsems(value : String) -> (Int64, Int64) raise ParseFail {
  if !value.contains(".") {
    (pint(value), 0L)
  } else {
    let parts = value.split(".").collect()
    if parts.length() != 2 {
      raise ParseFail("too many values to unpack")
    }
    let i = parts[0].to_owned()
    let mut f = parts[1].to_owned()
    let n = py_len(f)
    if n < 6 {
      f = f + String::make(6 - n, '0')
    }
    (pint(i), pint(py_slice(f, 0, end=6)))
  }
}

///|
/// `parser._parse_min_sec`
fn parse_min_sec(value : Dec) -> (Int64, Int64?) raise DecimalInvalidOperation {
  let minute = value.ip
  let second = if value.mod1_nonzero() { Some(value.frac60()) } else { None }
  (minute, second)
}

///|
/// `parser._adjust_ampm`
fn adjust_ampm(hour : Int64, ampm : Int) -> Int64 {
  if hour < 12L && ampm == 1 {
    hour + 12L
  } else if hour == 12L && ampm == 0 {
    0L
  } else {
    hour
  }
}

///|
/// `parser._ampm_valid`: for fuzzy parsing, 'a' or 'am' (both valid English
/// words) may erroneously trigger the AM/PM flag.
fn ampm_valid(hour : Int64?, ampm : Int?, fuzzy : Bool) -> Bool raise ParseFail {
  let mut val_is_ampm = true
  // If there's already an AM/PM flag, this one isn't one.
  if fuzzy && ampm is Some(_) {
    val_is_ampm = false
  }
  match hour {
    // If AM/PM is found and hour is not, raise a ValueError
    None =>
      if fuzzy {
        val_is_ampm = false
      } else {
        raise ParseFail("No hour specified with AM or PM flag.")
      }
    Some(h) =>
      if !(0L <= h && h <= 12L) {
        // If AM/PM is found, it's a 12 hour clock, so raise
        // an error for invalid range
        if fuzzy {
          val_is_ampm = false
        } else {
          raise ParseFail("Invalid hour specified for 12-hour clock.")
        }
      }
  }
  val_is_ampm
}

///|
/// Python `x in string.ascii_uppercase` for every character.
fn all_ascii_upper(s : String) -> Bool {
  s.iter().all(c => c is ('A'..='Z'))
}

///|
priv struct TokenParser {
  info : ParserInfo
  tokens : Array[String]
  ymd : Ymd
  res : ParseResult
  fuzzy : Bool
}

///|
/// `parser._could_be_tzname`
fn TokenParser::could_be_tzname(
  self : TokenParser,
  hour : Int64?,
  tzname : String?,
  tzoffset : Int64?,
  token : String,
) -> Bool {
  hour is Some(_) &&
  tzname is None &&
  tzoffset is None &&
  py_len(token) <= 5 &&
  (all_ascii_upper(token) || self.info.utczone_list.contains(token))
}

///|
/// `parser._find_hms_idx`
fn TokenParser::find_hms_idx(
  self : TokenParser,
  idx : Int,
  allow_jump : Bool,
) -> Int? {
  let tokens = self.tokens
  let info = self.info
  let len_l = tokens.length()
  if idx + 1 < len_l && info.hms(tokens[idx + 1]) is Some(_) {
    // There is an "h", "m", or "s" label following this token.  We take
    // assign the upcoming label to the current token.
    // e.g. the "12" in 12h"
    Some(idx + 1)
  } else if allow_jump &&
    idx + 2 < len_l &&
    tokens[idx + 1] == " " &&
    info.hms(tokens[idx + 2]) is Some(_) {
    // There is a space and then an "h", "m", or "s" label.
    // e.g. the "12" in "12 h"
    Some(idx + 2)
  } else if idx > 0 && info.hms(tokens[idx - 1]) is Some(_) {
    // There is a "h", "m", or "s" preceding this token.  Since neither
    // of the previous cases was hit, there is no label following this
    // token, so we use the previous label.
    // e.g. the "04" in "12h04"
    Some(idx - 1)
  } else if 1 < idx &&
    idx == len_l - 1 &&
    tokens[idx - 1] == " " &&
    info.hms(tokens[idx - 2]) is Some(_) {
    // If we are looking at the final token, we allow for a
    // backward-looking check to skip over a space.
    Some(idx - 2)
  } else {
    None
  }
}

///|
/// `parser._parse_hms` -> (new_idx, hms)
fn TokenParser::parse_hms(
  self : TokenParser,
  idx : Int,
  hms_idx : Int,
) -> (Int, Int) {
  let hms = self.info.hms(self.tokens[hms_idx]).unwrap()
  if hms_idx > idx {
    (hms_idx, hms)
  } else {
    // Looking backwards, increment one.
    (idx, hms + 1)
  }
}

///|
/// `parser._assign_hms`
fn TokenParser::assign_hms(
  self : TokenParser,
  value_repr : String,
  hms : Int,
) -> Unit raise {
  // See GH issue #427, fixing float rounding
  let value = to_decimal(value_repr)
  let res = self.res
  if hms == 0 {
    // Hour
    res.hour = Some(value.ip)
    if value.mod1_nonzero() {
      res.minute = Some(value.frac60())
    }
  } else if hms == 1 {
    let (m, s) = parse_min_sec(value)
    res.minute = Some(m)
    res.second = s
  } else if hms == 2 {
    let (s, us) = parsems(value_repr)
    res.second = Some(s)
    res.microsecond = Some(us)
  }
}

///|
/// `parser._parse_numeric_token`: returns the index of the last consumed
/// token.
fn TokenParser::parse_numeric_token(self : TokenParser, idx : Int) -> Int raise {
  let tokens = self.tokens
  let info = self.info
  let ymd = self.ymd
  let res = self.res
  let mut idx = idx
  // Token is a number
  let value_repr = tokens[idx]
  let value = to_decimal(value_repr) catch {
    _ => raise ParseFail("Unknown numeric token")
  }
  let len_li = py_len(value_repr)
  let len_l = tokens.length()
  if ymd.length() == 3 &&
    (len_li == 2 || len_li == 4) &&
    res.hour is None &&
    (
      idx + 1 >= len_l ||
      (tokens[idx + 1] != ":" && info.hms(tokens[idx + 1]) is None)
    ) {
    // 19990101T23[59]
    let s = tokens[idx]
    res.hour = Some(pint(py_slice(s, 0, end=2)))
    if len_li == 4 {
      res.minute = Some(pint(py_slice(s, 2)))
    }
  } else if len_li == 6 || (len_li > 6 && py_find(tokens[idx], '.') == 6) {
    // YYMMDD or HHMMSS[.ss]
    let s = tokens[idx]
    if ymd.length() == 0 && !tokens[idx].contains(".") {
      ymd.append(Str(py_slice(s, 0, end=2)))
      ymd.append(Str(py_slice(s, 2, end=4)))
      ymd.append(Str(py_slice(s, 4)))
    } else {
      // 19990101T235959[.59]
      res.hour = Some(pint(py_slice(s, 0, end=2)))
      res.minute = Some(pint(py_slice(s, 2, end=4)))
      let (sec, us) = parsems(py_slice(s, 4))
      res.second = Some(sec)
      res.microsecond = Some(us)
    }
  } else if len_li == 8 || len_li == 12 || len_li == 14 {
    // YYYYMMDD
    let s = tokens[idx]
    ymd.append(Str(py_slice(s, 0, end=4)), label=LY)
    ymd.append(Str(py_slice(s, 4, end=6)))
    ymd.append(Str(py_slice(s, 6, end=8)))
    if len_li > 8 {
      res.hour = Some(pint(py_slice(s, 8, end=10)))
      res.minute = Some(pint(py_slice(s, 10, end=12)))
      if len_li > 12 {
        res.second = Some(pint(py_slice(s, 12)))
      }
    }
  } else if self.find_hms_idx(idx, true) is Some(hms_idx) {
    // HH[ ]h or MM[ ]m or SS[.ss][ ]s
    let (new_idx, hms) = self.parse_hms(idx, hms_idx)
    idx = new_idx
    self.assign_hms(value_repr, hms)
  } else if idx + 2 < len_l && tokens[idx + 1] == ":" {
    // HH:MM[:SS[.ss]]
    res.hour = Some(value.ip)
    let value = to_decimal(tokens[idx + 2])
    let (m, s) = parse_min_sec(value)
    res.minute = Some(m)
    res.second = s
    if idx + 4 < len_l && tokens[idx + 3] == ":" {
      let (sec, us) = parsems(tokens[idx + 4])
      res.second = Some(sec)
      res.microsecond = Some(us)
      idx += 2
    }
    idx += 2
  } else if idx + 1 < len_l && tokens[idx + 1] is ("-" | "/" | ".") {
    let sep = tokens[idx + 1]
    ymd.append(Str(value_repr))
    if idx + 2 < len_l && !info.jump(tokens[idx + 2]) {
      if py_isdigit(tokens[idx + 2]) {
        // 01-01[-01]
        ymd.append(Str(tokens[idx + 2]))
      } else {
        // 01-Jan[-01]
        match info.month(tokens[idx + 2]) {
          Some(m) => ymd.append(Whole(m.to_int64()), label=LM)
          None => raise ParseFail("")
        }
      }
      if idx + 3 < len_l && tokens[idx + 3] == sep {
        // We have three members
        let t4 = tok(tokens, idx + 4)
        match info.month(t4) {
          Some(m) => ymd.append(Whole(m.to_int64()), label=LM)
          None => ymd.append(Str(t4))
        }
        idx += 2
      }
      idx += 1
    }
    idx += 1
  } else if idx + 1 >= len_l || info.jump(tokens[idx + 1]) {
    if idx + 2 < len_l && info.ampm(tokens[idx + 2]) is Some(ampm) {
      // 12 am
      let hour = value.ip
      res.hour = Some(adjust_ampm(hour, ampm))
      idx += 1
    } else {
      // Year, month or day
      ymd.append(Num(value))
    }
    idx += 1
  } else if info.ampm(tokens[idx + 1]) is Some(ampm) && value.lt(24L) {
    // 12am
    let hour = value.ip
    res.hour = Some(adjust_ampm(hour, ampm))
    idx += 1
  } else if ymd.could_be_day(value) {
    ymd.append(Num(value))
  } else if !self.fuzzy {
    raise ParseFail("")
  }
  idx
}

///|
/// Python `s.find(c)` by code point.
fn py_find(s : String, c : Char) -> Int {
  for i, x in s.to_array() {
    if x == c {
      return i
    }
  }
  -1
}

///|
/// `parser._recombine_skipped`
fn recombine_skipped(
  tokens : Array[String],
  skipped_idxs : Array[Int],
) -> Array[String] {
  let skipped_tokens : Array[String] = []
  for i, idx in skipped_idxs {
    if i > 0 && idx - 1 == skipped_idxs[i - 1] {
      let last = skipped_tokens.length() - 1
      skipped_tokens[last] = skipped_tokens[last] + tokens[idx]
    } else {
      skipped_tokens.push(tokens[idx])
    }
  }
  skipped_tokens
}

///|
/// The body of `parser._parse` inside its `try` block.
fn TokenParser::run(
  self : TokenParser,
  yearfirst : Bool,
  dayfirst : Bool,
  skipped_idxs : Array[Int],
) -> Unit raise {
  let l = self.tokens
  let info = self.info
  let res = self.res
  let ymd = self.ymd
  let fuzzy = self.fuzzy
  let len_l = l.length()
  let mut i = 0
  while i < len_l {
    // Check if it's a number
    let value_repr = l[i]
    if py_float_ok(value_repr) {
      // Numeric token
      i = self.parse_numeric_token(i)
    } else if info.weekday(l[i]) is Some(value) {
      // Check weekday
      res.weekday = Some(value)
    } else if info.month(l[i]) is Some(value) {
      // Check month name
      ymd.append(Whole(value.to_int64()), label=LM)
      if i + 1 < len_l {
        if l[i + 1] is ("-" | "/") {
          // Jan-01[-99]
          let sep = l[i + 1]
          ymd.append(Str(tok(l, i + 2)))
          if i + 3 < len_l && l[i + 3] == sep {
            // Jan-01-99
            ymd.append(Str(tok(l, i + 4)))
            i += 2
          }
          i += 2
        } else if i + 4 < len_l &&
          l[i + 1] == " " &&
          l[i + 3] == " " &&
          info.pertain(l[i + 2]) {
          // Jan of 01
          // In this case, 01 is clearly year
          if py_isdigit(l[i + 4]) {
            // Convert it here to become unambiguous
            let value = pint(l[i + 4])
            let year = convertyear64(info, value, false)
            ymd.append(Str(year.to_string()), label=LY)
          }
          i += 4
        }
      }
    } else if info.ampm(l[i]) is Some(value) {
      // Check am/pm
      let val_is_ampm = ampm_valid(res.hour, res.ampm, fuzzy)
      if val_is_ampm {
        res.hour = Some(adjust_ampm(res.hour.unwrap(), value))
        res.ampm = Some(value)
      } else if fuzzy {
        skipped_idxs.push(i)
      }
    } else if self.could_be_tzname(res.hour, res.tzname, res.tzoffset, l[i]) {
      // Check for a timezone name
      res.tzname = Some(l[i])
      res.tzoffset = info.tzoffset(l[i]).map(x => x.to_int64())
      // Check for something like GMT+3, or BRST+3. Notice
      // that it doesn't mean "I am 3 hours after GMT", but
      // "my time +3 is GMT". If found, we reverse the
      // logic so that timezone parsing code will get it
      // right.
      if i + 1 < len_l && l[i + 1] is ("+" | "-") {
        l[i + 1] = if l[i + 1] == "+" { "-" } else { "+" }
        res.tzoffset = None
        if info.utczone(l[i]) {
          // With something like GMT+3, the timezone
          // is *not* GMT.
          res.tzname = None
        }
      }
    } else if res.hour is Some(_) && l[i] is ("+" | "-") {
      // Check for a numbered timezone
      let signal = if l[i] == "+" { 1L } else { -1L }
      let next = tok(l, i + 1)
      let len_li = py_len(next)
      let mut hour_offset = 0L
      let mut min_offset = 0L
      if len_li == 4 {
        // -0300
        hour_offset = pint(py_slice(next, 0, end=2))
        min_offset = pint(py_slice(next, 2))
      } else if i + 2 < len_l && l[i + 2] == ":" {
        // -03:00
        hour_offset = pint(next)
        min_offset = pint(tok(l, i + 3))
        i += 2
      } else if len_li <= 2 {
        // -[0]3
        hour_offset = pint(py_slice(next, 0, end=2))
        min_offset = 0L
      } else {
        raise ParseFail("")
      }
      res.tzoffset = Some(signal * offset_seconds(hour_offset, min_offset))
      // Look for a timezone name between parenthesis
      if i + 5 < len_l &&
        info.jump(l[i + 2]) &&
        l[i + 3] == "(" &&
        l[i + 5] == ")" &&
        3 <= py_len(l[i + 4]) &&
        self.could_be_tzname(res.hour, res.tzname, None, l[i + 4]) {
        // -0300 (BRST)
        res.tzname = Some(l[i + 4])
        i += 4
      }
      i += 1
    } else if !(info.jump(l[i]) || fuzzy) {
      // Check jumps
      raise ParseFail("")
    } else {
      skipped_idxs.push(i)
    }
    i += 1
  }
  // Process year/month/day
  let (year, month, day) = ymd.resolve_ymd(yearfirst, dayfirst)
  res.century_specified = ymd.century_specified
  res.year = year
  res.month = month
  res.day = day
}

///|
/// `hour_offset * 3600 + min_offset * 60`, saturating.
fn offset_seconds(hour_offset : Int64, min_offset : Int64) -> Int64 {
  let lim = INT_SATURATE / 3600L
  if hour_offset.abs() > lim || min_offset.abs() > lim {
    INT_SATURATE
  } else {
    hour_offset * 3600L + min_offset * 60L
  }
}

///|
/// `info.convertyear(value)` for a possibly huge Python int: values that do
/// not fit an `Int` are >= 100 and therefore unchanged by the default rule.
fn convertyear64(
  info : ParserInfo,
  year : Int64,
  century_specified : Bool,
) -> Int64 {
  if year >= -2147483648L && year <= 2147483647L {
    info.convertyear(year.to_int(), century_specified~).to_int64()
  } else {
    year
  }
}

///|
/// `parserinfo.validate(res)`
fn validate(info : ParserInfo, res : ParseResult) -> Bool {
  // move to info
  if res.year is Some(y) {
    res.year = Some(convertyear64(info, y, res.century_specified))
  }
  if (res.tzoffset == Some(0L) && res.tzname is None) ||
    res.tzname is Some("Z" | "z") {
    res.tzname = Some("UTC")
    res.tzoffset = Some(0L)
  } else if res.tzoffset != Some(0L) &&
    res.tzname is Some(name) &&
    info.utczone(name) {
    res.tzoffset = Some(0L)
  }
  true
}

///|
/// `parser._parse`: `None` when the string cannot be parsed, otherwise the
/// result and the skipped tokens.
fn parse_fields(
  info : ParserInfo,
  timestr : String,
  dayfirst : Bool?,
  yearfirst : Bool?,
  fuzzy : Bool,
) -> (ParseResult, Array[String])? raise {
  let dayfirst = dayfirst.unwrap_or(info.dayfirst)
  let yearfirst = yearfirst.unwrap_or(info.yearfirst)
  let res = ParseResult::new()
  let tokens = timelex_split(timestr) // Splits the timestr into tokens
  let skipped_idxs = []
  let tp = { info, tokens, ymd: Ymd::new(), res, fuzzy, }
  tp.run(yearfirst, dayfirst, skipped_idxs) catch {
    ParseFail(_) => return None
    e => raise e
  }
  if !validate(info, res) {
    return None
  }
  Some((res, recombine_skipped(tokens, skipped_idxs)))
}
