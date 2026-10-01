// dateutil `parser._tzparser`: the POSIX/GNU `TZ` string parser used by
// `tzstr`. It lives here (not in `parser`) to avoid a package cycle.

///|
/// `_tzparser._result._attr`: one transition rule.
priv struct TzRule {
  mut month : Int?
  mut week : Int?
  mut weekday : Int?
  mut yday : Int?
  mut jyday : Int?
  mut day : Int?
  mut time : Int?
}

///|
fn TzRule::new() -> TzRule {
  {
    month: None,
    week: None,
    weekday: None,
    yday: None,
    jyday: None,
    day: None,
    time: None,
  }
}

///|
/// `_tzparser._result`.
priv struct TzStrParse {
  mut stdabbr : String?
  mut stdoffset : Int?
  mut dstabbr : String?
  mut dstoffset : Int?
  start : TzRule
  end : TzRule
  mut any_unused_tokens : Bool
  /// dateutil raises `TypeError` mid-parse (see `parse_tzstr`).
  mut type_error : Bool
}

///|
/// Python `IndexError`/`ValueError`/`AssertionError` inside the parser,
/// all of which make `_tzparser.parse` return `None`.
priv suberror TzParseFail

///|
/// `re.split(r'([,:.]|[a-zA-Z]+|[0-9]+)', s)` without the empty strings:
/// separators, ASCII letter runs, ASCII digit runs, and the text between
/// them.
fn tz_tokens(s : String) -> Array[String] {
  let out : Array[String] = []
  let other = StringBuilder()
  fn flush_other() {
    let t = other.to_string()
    if t != "" {
      out.push(t)
      other.reset()
    }
  }

  let chars = s.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c is (',' | ':' | '.') {
      flush_other()
      out.push(c.to_string())
      i += 1
    } else if c is ('a'..='z' | 'A'..='Z') {
      flush_other()
      let b = StringBuilder()
      while i < n && chars[i] is ('a'..='z' | 'A'..='Z') {
        b.write_char(chars[i])
        i += 1
      }
      out.push(b.to_string())
    } else if c is ('0'..='9') {
      flush_other()
      let b = StringBuilder()
      while i < n && chars[i] is ('0'..='9') {
        b.write_char(chars[i])
        i += 1
      }
      out.push(b.to_string())
    } else {
      other.write_char(c)
      i += 1
    }
  }
  flush_other()
  out
}

///|
/// Python `int(token)` for the tokens the parser can see (digit runs);
/// anything else is a `ValueError`.
fn tz_int(s : String) -> Int raise TzParseFail {
  if s.length() == 0 || s.length() > 9 {
    // Longer digit runs would need Python big integers; treat them as
    // invalid (dateutil would fail later anyway).
    raise TzParseFail
  }
  let mut v = 0
  for c in s {
    guard c is ('0'..='9') else { raise TzParseFail }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  v
}

///|
fn tz_tok(l : Array[String], i : Int) -> String raise TzParseFail {
  guard l.get(i) is Some(t) else { raise TzParseFail }
  t
}

///|
/// Python `s[a:b]` on a token.
fn tz_slice(s : String, a : Int, b : Int) -> String {
  py_slice(s, a, b)
}

///|
fn tz_has_any(s : String, chars : String) -> Bool {
  for c in s {
    if chars.contains_char(c) {
      return true
    }
  }
  false
}

///|
fn tz_all_in(s : String, chars : String) -> Bool {
  for c in s {
    if !chars.contains_char(c) {
      return false
    }
  }
  true
}

///|
fn tz_count(l : ArrayView[String], s : String) -> Int {
  let mut n = 0
  for x in l {
    if x == s {
      n += 1
    }
  }
  n
}

///|
/// `_tzparser.parse(tzstr)`: `None` if the string cannot be parsed.
/// Raises `TypeError` where dateutil does (a dateutil-format DST offset
/// with no standard offset).
fn parse_tzstr(tzstr : String) -> TzStrParse? raise @datetime.DateTimeError {
  let res = TzStrParse::{
    stdabbr: None,
    stdoffset: None,
    dstabbr: None,
    dstoffset: None,
    start: TzRule::new(),
    end: TzRule::new(),
    any_unused_tokens: false,
    type_error: false,
  }
  let l = tz_tokens(tzstr)
  let used_idxs : Array[Int] = []
  let len_l = l.length()
  let ok = parse_tzstr_tokens(res, l, used_idxs) catch { TzParseFail => false }
  if !ok {
    return None
  }
  if res.type_error {
    raise @datetime.TypeError(
      "unsupported operand type(s) for +: 'NoneType' and 'int'",
    )
  }
  let used = Array::make(len_l, false)
  for idx in used_idxs {
    if idx >= 0 && idx < len_l {
      used[idx] = true
    }
  }
  let mut unused = false
  for n in 0..<len_l {
    if !used[n] && !(l[n] is ("," | ":")) {
      unused = true
    }
  }
  res.any_unused_tokens = unused
  Some(res)
}

///|
/// The body of `_tzparser.parse`; `false` stands for `return None`.
fn parse_tzstr_tokens(
  res : TzStrParse,
  l : Array[String],
  used_idxs : Array[Int],
) -> Bool raise TzParseFail {
  let len_l = l.length()
  let mut i = 0
  while i < len_l {
    // BRST+3[BRDT[+2]]
    let mut j = i
    while j < len_l && !tz_has_any(l[j], "0123456789:,-+") {
      j += 1
    }
    if j != i {
      let is_std = res.stdabbr is None
      let abbr = l[i:j].iter().fold(init="", (a, b) => a + b)
      if is_std {
        res.stdabbr = Some(abbr)
      } else {
        res.dstabbr = Some(abbr)
      }
      for ii in 0..<j {
        used_idxs.push(ii)
      }
      i = j
      if i < len_l &&
        (l[i] is ("+" | "-") || tz_has_any(tz_slice(l[i], 0, 1), "0123456789")) {
        let signal = if l[i] is ("+" | "-") {
          // Yes, that's right.  See the TZ variable documentation.
          let s = if l[i] == "+" { -1 } else { 1 }
          used_idxs.push(i)
          i += 1
          s
        } else {
          -1
        }
        let tok = tz_tok(l, i)
        let len_li = tok.length()
        let offset = if len_li == 4 {
          // -0300
          (
            tz_int(tz_slice(tok, 0, 2)) * 3600 +
            tz_int(tz_slice(tok, 2, 4)) * 60
          ) *
          signal
        } else if i + 1 < len_l && l[i + 1] == ":" {
          // -03:00
          let v = (tz_int(tok) * 3600 + tz_int(tz_tok(l, i + 2)) * 60) * signal
          used_idxs.push(i)
          i += 2
          v
        } else if len_li <= 2 {
          // -[0]3
          tz_int(tz_slice(tok, 0, 2)) * 3600 * signal
        } else {
          return false
        }
        if is_std {
          res.stdoffset = Some(offset)
        } else {
          res.dstoffset = Some(offset)
        }
        used_idxs.push(i)
        i += 1
      }
      if res.dstabbr is Some(_) {
        break
      }
    } else {
      break
    }
  }
  if i < len_l {
    for jj in i..<len_l {
      if l[jj] == ";" {
        l[jj] = ","
      }
    }
    if l[i] != "," {
      raise TzParseFail
    }
    i += 1
  }
  if i >= len_l {
    ()
  } else if tz_count(l, ",") is (8 | 9) &&
    l[i:].iter().all(x => x == "," || tz_all_in(x, "0123456789+-")) {
    // GMT0BST,3,0,30,3600,10,0,26,7200[,3600]
    for x in [res.start, res.end] {
      x.month = Some(tz_int(tz_tok(l, i)))
      used_idxs.push(i)
      i += 2
      let value = if tz_tok(l, i) == "-" {
        let v = tz_int(tz_tok(l, i + 1)) * -1
        used_idxs.push(i)
        i += 1
        v
      } else {
        tz_int(tz_tok(l, i))
      }
      used_idxs.push(i)
      i += 2
      if value != 0 {
        x.week = Some(value)
        x.weekday = Some(@datetime.floor_mod(tz_int(tz_tok(l, i)) - 1, 7))
      } else {
        x.day = Some(tz_int(tz_tok(l, i)))
      }
      used_idxs.push(i)
      i += 2
      x.time = Some(tz_int(tz_tok(l, i)))
      used_idxs.push(i)
      i += 2
    }
    if i < len_l {
      let signal = if l[i] is ("-" | "+") {
        let s = if l[i] == "+" { 1 } else { -1 }
        used_idxs.push(i)
        i += 1
        s
      } else {
        1
      }
      used_idxs.push(i)
      let delta = tz_int(tz_tok(l, i)) * signal
      guard res.stdoffset is Some(stdoffset) else {
        // Python: `None + int` raises TypeError (not caught by the parser)
        res.type_error = true
        return true
      }
      res.dstoffset = Some(stdoffset + delta)
    }
    // (dateutil warns that this format is deprecated.)
  } else if tz_count(l, ",") == 2 &&
    tz_count(l[i:], "/") <= 2 &&
    l[i:]
    .iter()
    .all(x => {
      x is ("," | "/" | "J" | "M" | "." | "-" | ":") ||
      tz_all_in(x, "0123456789")
    }) {
    for x in [res.start, res.end] {
      if tz_tok(l, i) == "J" {
        // non-leap year day (1 based)
        used_idxs.push(i)
        i += 1
        x.jyday = Some(tz_int(tz_tok(l, i)))
      } else if l[i] == "M" {
        // month[-.]week[-.]weekday
        used_idxs.push(i)
        i += 1
        x.month = Some(tz_int(tz_tok(l, i)))
        used_idxs.push(i)
        i += 1
        if !(tz_tok(l, i) is ("-" | ".")) {
          raise TzParseFail
        }
        used_idxs.push(i)
        i += 1
        let week = tz_int(tz_tok(l, i))
        x.week = Some(if week == 5 { -1 } else { week })
        used_idxs.push(i)
        i += 1
        if !(tz_tok(l, i) is ("-" | ".")) {
          raise TzParseFail
        }
        used_idxs.push(i)
        i += 1
        x.weekday = Some(@datetime.floor_mod(tz_int(tz_tok(l, i)) - 1, 7))
      } else {
        // year day (zero based)
        x.yday = Some(tz_int(l[i]) + 1)
      }
      used_idxs.push(i)
      i += 1
      if i < len_l && l[i] == "/" {
        used_idxs.push(i)
        i += 1
        // start time
        let tok = tz_tok(l, i)
        let len_li = tok.length()
        if len_li == 4 {
          // -0300
          x.time = Some(
            tz_int(tz_slice(tok, 0, 2)) * 3600 +
            tz_int(tz_slice(tok, 2, 4)) * 60,
          )
        } else if i + 1 < len_l && l[i + 1] == ":" {
          // -03:00
          x.time = Some(tz_int(tok) * 3600 + tz_int(tz_tok(l, i + 2)) * 60)
          used_idxs.push(i)
          i += 2
          if i + 1 < len_l && l[i + 1] == ":" {
            used_idxs.push(i)
            i += 2
            x.time = Some(x.time.unwrap_or(0) + tz_int(tz_tok(l, i)))
          }
        } else if len_li <= 2 {
          // -[0]3
          x.time = Some(tz_int(tz_slice(tok, 0, 2)) * 3600)
        } else {
          return false
        }
        used_idxs.push(i)
        i += 1
      }
      if !(i == len_l || tz_tok(l, i) == ",") {
        raise TzParseFail
      }
      i += 1
    }
    if !(i >= len_l) {
      raise TzParseFail
    }
  }
  true
}
