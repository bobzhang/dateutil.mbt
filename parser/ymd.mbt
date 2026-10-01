// dateutil `_ymd` (year/month/day candidate list) and the `Decimal`
// subset the parser uses for numeric tokens.

///|
/// Internal failure of `parser._parse` (Python: `IndexError`/`ValueError`
/// caught by `_parse`, which then returns `(None, None)`).
priv suberror ParseFail {
  ParseFail(String)
}

///|
/// `Decimal(token)` for the finite, non-negative values the tokenizer can
/// produce: `ip` is the integer part (saturating), `frac` the fraction
/// digits (ASCII).
priv struct Dec {
  ip : Int64
  frac : String
}

///|
fn ascii_digits(chars : ArrayView[Char]) -> String {
  let sb = StringBuilder()
  for c in chars {
    if c != '_' {
      sb.write_char(Int::unsafe_to_char('0'.to_int() + py_decimal_value(c)))
    }
  }
  sb.to_string()
}

///|
fn digits_to_int64(s : String) -> Int64 {
  let mut v = 0L
  for c in s {
    if v < INT_SATURATE {
      v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
    }
  }
  if v > INT_SATURATE {
    INT_SATURATE
  } else {
    v
  }
}

///|
/// `parser._to_decimal(val)`: Python `Decimal(val)`, rejecting non-finite
/// values. Signs never occur in tokens and are rejected.
fn to_decimal(val : String) -> Dec raise ParseFail {
  let chars = py_strip(val)
  guard decimal_shape(chars[:]) is Some((int_part, frac_part, exp)) else {
    raise ParseFail("Could not convert \{val} to decimal")
  }
  let digits = ascii_digits(int_part) + ascii_digits(frac_part)
  let n = digits.length()
  let point = int_part.length().to_int64() + exp
  if point <= 0L {
    let zeros = if point < -1000L { 1000 } else { (-point).to_int() }
    { ip: 0L, frac: String::make(zeros, '0') + digits, }
  } else if point >= n.to_int64() {
    let ip = if point - n.to_int64() > 20L {
      if digits_to_int64(digits) == 0L {
        0L
      } else {
        INT_SATURATE
      }
    } else {
      digits_to_int64(
        digits + String::make((point - n.to_int64()).to_int(), '0'),
      )
    }
    { ip, frac: "", }
  } else {
    let p = point.to_int()
    {
      ip: digits_to_int64(digits.unsafe_substring(start=0, end=p)),
      frac: digits.unsafe_substring(start=p, end=n),
    }
  }
}

///|
/// `value % 1` is non-zero.
fn Dec::has_frac(self : Dec) -> Bool {
  self.frac.iter().any(c => c != '0')
}

///|
/// `int(60 * (value % 1))`, computed exactly.
fn Dec::frac60(self : Dec) -> Int64 {
  let mut carry = 0
  for c in self.frac.rev_iter() {
    let t = (c.to_int() - '0'.to_int()) * 60 + carry
    carry = t / 10
  }
  carry.to_int64()
}

///|
/// `value > n`
fn Dec::gt(self : Dec, n : Int64) -> Bool {
  self.ip > n || (self.ip == n && self.has_frac())
}

///|
/// `value <= n`
fn Dec::le(self : Dec, n : Int64) -> Bool {
  !self.gt(n)
}

///|
/// `value < n`
fn Dec::lt(self : Dec, n : Int64) -> Bool {
  self.ip < n
}

///|
/// What `_ymd.append` receives: a string token, a `Decimal`, or an `int`.
priv enum YmdVal {
  Str(String)
  Num(Dec)
  Whole(Int64)
}

///|
/// The `_ymd.append` labels 'Y', 'M', 'D' (the parser itself never passes
/// 'D'; only the internals test does).
#warnings("-unused_constructor")
priv enum YmdLabel {
  LY
  LM
  LD
}

///|
priv struct Ymd {
  vals : Array[Int64]
  mut century_specified : Bool
  mut dstridx : Int?
  mut mstridx : Int?
  mut ystridx : Int?
}

///|
fn Ymd::new() -> Ymd {
  {
    vals: [],
    century_specified: false,
    dstridx: None,
    mstridx: None,
    ystridx: None,
  }
}

///|
fn Ymd::length(self : Ymd) -> Int {
  self.vals.length()
}

///|
/// Python calendar month lengths for any (possibly out-of-range) year.
fn days_in_month64(year : Int64, month : Int64) -> Int raise ParseFail {
  if month < 1L || month > 12L {
    raise ParseFail("bad month number \{month}; must be 1-12")
  }
  let m = month.to_int()
  if m == 2 {
    let y = year % 400L
    let y = if y < 0L { y + 400L } else { y }
    let leap = y % 4L == 0L && (y % 100L != 0L || y == 0L)
    if leap {
      29
    } else {
      28
    }
  } else {
    @datetime.days_in_month(2001, m)
  }
}

///|
fn Ymd::could_be_day(self : Ymd, value : Dec) -> Bool raise ParseFail {
  if self.dstridx is Some(_) {
    false
  } else {
    match (self.mstridx, self.ystridx) {
      (None, _) => value.ip >= 1L && value.le(31L)
      (Some(mi), None) => {
        // Be permissive, assume leap year
        let month = self.vals[mi]
        value.ip >= 1L && value.le(days_in_month64(2000L, month).to_int64())
      }
      (Some(mi), Some(yi)) => {
        let month = self.vals[mi]
        let year = self.vals[yi]
        value.ip >= 1L && value.le(days_in_month64(year, month).to_int64())
      }
    }
  }
}

///|
fn Ymd::append(
  self : Ymd,
  val : YmdVal,
  label? : YmdLabel,
) -> Unit raise ParseFail {
  let mut label = label
  let big = match val {
    Str(s) => py_isdigit(s) && py_len(s) > 2
    Num(d) => d.gt(100L)
    Whole(v) => v > 100L
  }
  if big {
    self.century_specified = true
    if label is Some(LM | LD) {
      raise ParseFail("label")
    }
    label = Some(LY)
  }
  let v = match val {
    Str(s) => py_int(s) catch { e => raise ParseFail(e.to_string()) }
    Num(d) => d.ip
    Whole(v) => v
  }
  self.vals.push(v)
  let idx = self.vals.length() - 1
  match label {
    Some(LM) => {
      if self.mstridx is Some(_) {
        raise ParseFail("Month is already set")
      }
      self.mstridx = Some(idx)
    }
    Some(LD) => {
      if self.dstridx is Some(_) {
        raise ParseFail("Day is already set")
      }
      self.dstridx = Some(idx)
    }
    Some(LY) => {
      if self.ystridx is Some(_) {
        raise ParseFail("Year is already set")
      }
      self.ystridx = Some(idx)
    }
    None => ()
  }
}

///|
/// `_ymd.resolve_ymd(yearfirst, dayfirst)` -> (year, month, day).
fn Ymd::resolve_ymd(
  self : Ymd,
  yearfirst : Bool,
  dayfirst : Bool,
) -> (Int64?, Int64?, Int64?) raise ParseFail {
  let len_ymd = self.length()
  let v = self.vals
  let mut n_strids = 0
  for s in [self.ystridx, self.mstridx, self.dstridx] {
    if s is Some(_) {
      n_strids += 1
    }
  }
  if (len_ymd == n_strids && n_strids > 0) || (len_ymd == 3 && n_strids == 2) {
    // _resolve_from_stridxs
    let mut y = self.ystridx
    let mut m = self.mstridx
    let mut d = self.dstridx
    if len_ymd == 3 && n_strids == 2 {
      // we can back out the remaining stridx value
      let used = [y, m, d]
      let mut missing = 0
      for x in 0..<3 {
        if !used.contains(Some(x)) {
          missing = x
        }
      }
      if y is None {
        y = Some(missing)
      } else if m is None {
        m = Some(missing)
      } else {
        d = Some(missing)
      }
    }
    return (y.map(i => v[i]), m.map(i => v[i]), d.map(i => v[i]))
  }
  let mstridx = self.mstridx
  let mut year = None
  let mut month = None
  let mut day = None
  if len_ymd > 3 {
    raise ParseFail("More than three YMD values")
  } else if len_ymd == 1 || (mstridx is Some(_) && len_ymd == 2) {
    // One member, or two members with a month string
    let other = match mstridx {
      Some(mi) => {
        month = Some(v[mi])
        // since mstridx is 0 or 1, self[mstridx-1] always
        // looks up the other element
        v[(mi + len_ymd - 1) % len_ymd]
      }
      None => v[0]
    }
    if len_ymd > 1 || mstridx is None {
      if other > 31L {
        year = Some(other)
      } else {
        day = Some(other)
      }
    }
  } else if len_ymd == 2 {
    // Two members with numbers
    if v[0] > 31L {
      // 99-01
      year = Some(v[0])
      month = Some(v[1])
    } else if v[1] > 31L {
      // 01-99
      month = Some(v[0])
      year = Some(v[1])
    } else if dayfirst && v[1] <= 12L {
      // 13-01
      day = Some(v[0])
      month = Some(v[1])
    } else {
      // 01-13
      month = Some(v[0])
      day = Some(v[1])
    }
  } else if len_ymd == 3 {
    // Three members
    let (a, b, c) = (v[0], v[1], v[2])
    let (y, m, d) = match mstridx {
      Some(0) =>
        if b > 31L {
          // Apr-2003-25
          (b, a, c)
        } else {
          (c, a, b)
        }
      Some(1) =>
        if a > 31L || (yearfirst && c <= 31L) {
          // 99-Jan-01
          (a, b, c)
        } else {
          // 01-Jan-01
          // Give precedence to day-first, since
          // two-digit years is usually hand-written.
          (c, b, a)
        }
      Some(_) =>
        // WTF!?
        if b > 31L {
          // 01-99-Jan
          (b, c, a)
        } else {
          // 99-01-Jan
          (a, c, b)
        }
      None =>
        if a > 31L ||
          self.ystridx == Some(0) ||
          (yearfirst && b <= 12L && c <= 31L) {
          // 99-01-01
          if dayfirst && c <= 12L {
            (a, c, b)
          } else {
            (a, b, c)
          }
        } else if a > 12L || (dayfirst && b <= 12L) {
          // 13-01-01
          (c, b, a)
        } else {
          // 01-13-01
          (c, a, b)
        }
    }
    year = Some(y)
    month = Some(m)
    day = Some(d)
  }
  (year, month, day)
}
