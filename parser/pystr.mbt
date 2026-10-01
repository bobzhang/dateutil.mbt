// Python `str` semantics needed by the parser: character classes
// (`isalpha`/`isdigit`/`isspace`), `lower()`, code-point length and
// slicing, and the `int()` / `float()` / `Decimal()` string grammars.

///|
priv struct RangeTable {
  starts : Array[Int]
  ends : Array[Int]
}

///|
fn parse_hex(s : StringView) -> Int {
  let mut v = 0
  for c in s {
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      'A'..='F' => c.to_int() - 'A'.to_int() + 10
      _ => abort("bad hex digit")
    }
    v = v * 16 + d
  }
  v
}

///|
fn split_ws(src : String) -> Array[StringView] {
  let out = []
  for part in src.split(" ") {
    for p in part.split("\n") {
      if p.length() > 0 {
        out.push(p)
      }
    }
  }
  out
}

///|
fn parse_ranges(src : String) -> RangeTable {
  let starts = []
  let ends = []
  for item in split_ws(src) {
    match item.find("-") {
      Some(i) => {
        starts.push(parse_hex(item[:i]))
        ends.push(parse_hex(item[i + 1:]))
      }
      None => {
        let v = parse_hex(item)
        starts.push(v)
        ends.push(v)
      }
    }
  }
  { starts, ends, }
}

///|
/// Index of the last range whose start is `<= c`, or -1.
fn bsearch_start(starts : Array[Int], c : Int) -> Int {
  for lo = 0, hi = starts.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if starts[mid] <= c {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo - 1
  }
}

///|
fn RangeTable::find(self : RangeTable, c : Int) -> Int {
  let i = bsearch_start(self.starts, c)
  if i >= 0 && c <= self.ends[i] {
    i
  } else {
    -1
  }
}

///|
let alpha_table : RangeTable = parse_ranges(alpha_ranges_src)

///|
let digit_table : RangeTable = parse_ranges(digit_ranges_src)

///|
let space_table : RangeTable = parse_ranges(space_ranges_src)

///|
let decimal_table : RangeTable = parse_ranges(decimal_ranges_src)

///|
priv struct LowerRuns {
  starts : Array[Int]
  ends : Array[Int]
  steps : Array[Int]
  deltas : Array[Int]
}

///|
let lower_runs : LowerRuns = {
  let starts = []
  let ends = []
  let steps = []
  let deltas = []
  for item in split_ws(lower_runs_src) {
    let parts = item.split(":").collect()
    starts.push(parse_hex(parts[0]))
    ends.push(parse_hex(parts[1]))
    steps.push(@string.parse_int(parts[2]) catch { _ => abort("bad step") })
    deltas.push(@string.parse_int(parts[3]) catch { _ => abort("bad delta") })
  }
  { starts, ends, steps, deltas, }
}

///|
/// Python `ch.isalpha()`.
fn py_isalpha_char(c : Char) -> Bool {
  if c.to_int() < 128 {
    c is ('a'..='z' | 'A'..='Z')
  } else {
    alpha_table.find(c.to_int()) >= 0
  }
}

///|
/// Python `ch.isdigit()`.
fn py_isdigit_char(c : Char) -> Bool {
  if c.to_int() < 128 {
    c is ('0'..='9')
  } else {
    digit_table.find(c.to_int()) >= 0
  }
}

///|
/// Python `ch.isspace()`.
fn py_isspace_char(c : Char) -> Bool {
  if c.to_int() < 128 {
    c is (' ' | '\t'..='\r' | '\u{1c}'..='\u{1f}')
  } else {
    space_table.find(c.to_int()) >= 0
  }
}

///|
/// The value of a Unicode decimal digit (`str.isdecimal()`), or -1.
fn py_decimal_value(c : Char) -> Int {
  let ci = c.to_int()
  if ci < 128 {
    if c is ('0'..='9') {
      ci - '0'.to_int()
    } else {
      -1
    }
  } else {
    let i = decimal_table.find(ci)
    if i >= 0 {
      (ci - decimal_table.starts[i]) % 10
    } else {
      -1
    }
  }
}

///|
fn lower_char_simple(c : Char) -> Char {
  let ci = c.to_int()
  if ci < 128 {
    return c.to_ascii_lowercase()
  }
  let i = bsearch_start(lower_runs.starts, ci)
  if i >= 0 &&
    ci <= lower_runs.ends[i] &&
    (ci - lower_runs.starts[i]) % lower_runs.steps[i] == 0 {
    Int::unsafe_to_char(ci + lower_runs.deltas[i])
  } else {
    c
  }
}

///|
let cased_table : RangeTable = parse_ranges(cased_ranges_src)

///|
let case_ignorable_table : RangeTable = parse_ranges(case_ignorable_ranges_src)

///|
/// CPython `handle_capital_sigma`: a cased letter precedes (skipping
/// case-ignorable characters) and none follows.
fn final_sigma(chars : Array[Char], i : Int) -> Bool {
  let ignorable = (c : Char) => case_ignorable_table.find(c.to_int()) >= 0
  let cased = (c : Char) => cased_table.find(c.to_int()) >= 0
  let mut j = i - 1
  while j >= 0 && ignorable(chars[j]) {
    j -= 1
  }
  if !(j >= 0 && cased(chars[j])) {
    return false
  }
  j = i + 1
  while j < chars.length() && ignorable(chars[j]) {
    j += 1
  }
  j == chars.length() || !cased(chars[j])
}

///|
/// Python `s.lower()` (full case mapping: U+0130 becomes two code points and
/// a capital sigma in final position becomes a final sigma, following
/// CPython's `handle_capital_sigma`).
fn py_lower(s : String) -> String {
  let mut ascii = true
  for c in s {
    if c.to_int() >= 128 || c is ('A'..='Z') {
      ascii = false
      break
    }
  }
  if ascii {
    return s
  }
  let chars = s.to_array()
  let sb = StringBuilder()
  for i, c in chars {
    if c == '\u{130}' {
      sb.write_char('i')
      sb.write_char('\u{307}')
    } else if c == '\u{3a3}' {
      sb.write_char(if final_sigma(chars, i) { '\u{3c2}' } else { '\u{3c3}' })
    } else {
      sb.write_char(lower_char_simple(c))
    }
  }
  sb.to_string()
}

///|
/// Python `s.isdigit()`: non-empty and all characters are digits.
fn py_isdigit(s : String) -> Bool {
  s.length() > 0 && s.iter().all(py_isdigit_char)
}

///|
/// Python `len(s)`: the number of code points.
fn py_len(s : String) -> Int {
  s.char_length()
}

///|
/// Python `s[start:end]` for non-negative indices (clamped), by code point.
fn py_slice(s : String, start : Int, end? : Int) -> String {
  let n = py_len(s)
  let end = match end {
    Some(e) => if e > n { n } else { e }
    None => n
  }
  let start = if start > n { n } else { start }
  if start >= end {
    return ""
  }
  if n == s.length() {
    return s.unsafe_substring(start~, end~)
  }
  String::from_array(s.to_array()[start:end])
}

///|
/// Python `s.count(c)` for a single character.
fn py_count(s : String, c : Char) -> Int {
  let mut n = 0
  for x in s {
    if x == c {
      n += 1
    }
  }
  n
}

///|
/// Python `s[-1]` for a non-empty string.
fn py_last(s : String) -> Char {
  s.rev_iter().next().unwrap()
}

///|
/// Strip Python whitespace (`str.strip()`).
fn py_strip(s : String) -> Array[Char] {
  let chars = s.to_array()
  let mut a = 0
  let mut b = chars.length()
  while a < b && py_isspace_char(chars[a]) {
    a += 1
  }
  while b > a && py_isspace_char(chars[b - 1]) {
    b -= 1
  }
  chars[a:b].to_owned()
}

///|
/// Largest magnitude we track for parsed integers; larger values saturate.
/// Anything above `Int` range is reported as an `OverflowError` before it is
/// used as a datetime field, so saturation only affects error messages for
/// absurdly long digit strings.
const INT_SATURATE : Int64 = 1000000000000000000L

///|
/// Accumulate decimal digits (with Python's single `_` separators) into a
/// saturating `Int64`. Returns `None` if `chars` is not a valid digit run.
fn digits_value(chars : ArrayView[Char], allow_underscore : Bool) -> Int64? {
  if chars.length() == 0 {
    return None
  }
  let mut v = 0L
  let mut prev_digit = false
  for c in chars {
    if c == '_' && allow_underscore {
      if !prev_digit {
        return None
      }
      prev_digit = false
      continue
    }
    let d = py_decimal_value(c)
    if d < 0 {
      return None
    }
    v = sat_push(v, d)
    prev_digit = true
  }
  if !prev_digit {
    return None
  }
  Some(v)
}

///|
/// `v * 10 + d`, saturating at `INT_SATURATE`.
fn sat_push(v : Int64, d : Int) -> Int64 {
  if v >= (INT_SATURATE - d.to_int64()) / 10L {
    INT_SATURATE
  } else {
    v * 10L + d.to_int64()
  }
}

///|
/// CPython's default `sys.get_int_max_str_digits()`.
const INT_MAX_STR_DIGITS : Int = 4300

///|
/// Python `int(s)` (base 10) for `str` input. Values beyond 10**18 saturate;
/// strings of more than 4300 digits raise `ValueError` like CPython's default
/// integer string conversion limit.
fn py_int(s : String) -> Int64 raise @datetime.DateTimeError {
  let chars = py_strip(s)
  let (neg, body) = match chars {
    ['-', .. rest] => (true, rest)
    ['+', .. rest] => (false, rest)
    _ => (false, chars[:])
  }
  match digits_value(body, true) {
    Some(v) => {
      let ndigits = body.iter().filter(c => c != '_').count()
      if ndigits > INT_MAX_STR_DIGITS {
        raise @datetime.ValueError(
          "Exceeds the limit (4300 digits) for integer string conversion: value has \{ndigits} digits; use sys.set_int_max_str_digits() to increase the limit",
        )
      }
      if neg {
        -v
      } else {
        v
      }
    }
    None =>
      raise @datetime.ValueError(
        "invalid literal for int() with base 10: \{@datetime.py_str_repr(s)}",
      )
  }
}

///|
fn to_c_int(v : Int64) -> Int raise @datetime.DateTimeError {
  if v > 2147483647L || v < -2147483648L {
    raise @datetime.OverflowError("Python int too large to convert to C int")
  }
  v.to_int()
}

///|
/// Python `float(s)` succeeds. Only the shapes reachable from timelex tokens
/// matter (no whitespace inside tokens), but the full grammar is cheap.
fn py_float_ok(s : String) -> Bool {
  let chars = py_strip(s)
  let body = match chars {
    ['-' | '+', .. rest] => rest
    _ => chars[:]
  }
  let lowered = py_lower(String::from_array(body))
  if lowered is ("inf" | "infinity" | "nan") {
    return true
  }
  decimal_shape(body) is Some(_)
}

///|
/// Parses `digits [. digits] [e [sign] digits]` (or `. digits ...`) and
/// returns (integer digits, fraction digits, exponent), or `None`.
fn decimal_shape(
  body : ArrayView[Char],
) -> (ArrayView[Char], ArrayView[Char], Int64)? {
  let n = body.length()
  let mut i = 0
  while i < n && (py_decimal_value(body[i]) >= 0 || body[i] == '_') {
    i += 1
  }
  let int_part = body[0:i]
  let mut frac_part = body[i:i]
  if i < n && body[i] == '.' {
    let j = i + 1
    i = j
    while i < n && (py_decimal_value(body[i]) >= 0 || body[i] == '_') {
      i += 1
    }
    frac_part = body[j:i]
  }
  if int_part.length() == 0 && frac_part.length() == 0 {
    return None
  }
  if int_part.length() > 0 && digits_value(int_part, true) is None {
    return None
  }
  if frac_part.length() > 0 && digits_value(frac_part, true) is None {
    return None
  }
  let mut exp = 0L
  if i < n && (body[i] == 'e' || body[i] == 'E') {
    let mut j = i + 1
    let mut neg = false
    if j < n && (body[j] == '+' || body[j] == '-') {
      neg = body[j] == '-'
      j += 1
    }
    guard digits_value(body[j:n], true) is Some(e) else { return None }
    exp = if neg { -e } else { e }
    i = n
  }
  if i != n {
    return None
  }
  Some((int_part, frac_part, exp))
}
