// Python `str` method semantics used by `rrulestr`.

///|
/// Python `str.isspace()` for a single UTF-16 code unit.
fn is_py_space(c : UInt16) -> Bool {
  let c = c.to_int()
  (c >= 0x09 && c <= 0x0d) ||
  (c >= 0x1c && c <= 0x20) ||
  c == 0x85 ||
  c == 0xa0 ||
  c == 0x1680 ||
  (c >= 0x2000 && c <= 0x200a) ||
  c == 0x2028 ||
  c == 0x2029 ||
  c == 0x202f ||
  c == 0x205f ||
  c == 0x3000
}

///|
/// Python line boundaries for `str.splitlines()` (`\r` handled separately).
fn is_py_linebreak(c : UInt16) -> Bool {
  let c = c.to_int()
  c == 0x0a ||
  c == 0x0b ||
  c == 0x0c ||
  c == 0x1c ||
  c == 0x1d ||
  c == 0x1e ||
  c == 0x85 ||
  c == 0x2028 ||
  c == 0x2029
}

///|
/// Python `str.upper()`. Only ASCII letters are mapped (see PORTING.md).
fn py_upper(s : String) -> String {
  s.to_upper()
}

///|
/// Python `str.strip()`.
fn py_strip(s : String) -> String {
  let mut i = 0
  let mut j = s.length()
  while i < j && is_py_space(s[i]) {
    i += 1
  }
  while j > i && is_py_space(s[j - 1]) {
    j -= 1
  }
  s.unsafe_substring(start=i, end=j)
}

///|
/// Python `str.rstrip()`.
fn py_rstrip(s : String) -> String {
  let mut j = s.length()
  while j > 0 && is_py_space(s[j - 1]) {
    j -= 1
  }
  s.unsafe_substring(start=0, end=j)
}

///|
/// Python `str.split()` (no argument): split on runs of whitespace.
fn py_split_ws(s : String) -> Array[String] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    while i < n && is_py_space(s[i]) {
      i += 1
    }
    if i >= n {
      break
    }
    let start = i
    while i < n && !is_py_space(s[i]) {
      i += 1
    }
    out.push(s.unsafe_substring(start~, end=i))
  }
  out
}

///|
/// Python `str.splitlines()`.
fn py_splitlines(s : String) -> Array[String] {
  let out = []
  let n = s.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    let c = s[i]
    if c == '\r' {
      out.push(s.unsafe_substring(start~, end=i))
      i += if i + 1 < n && s[i + 1] == '\n' { 2 } else { 1 }
      start = i
    } else if is_py_linebreak(c) {
      out.push(s.unsafe_substring(start~, end=i))
      i += 1
      start = i
    } else {
      i += 1
    }
  }
  if start < n {
    out.push(s.unsafe_substring(start~, end=n))
  }
  out
}

///|
/// Python `int(s)` for base-10 strings: surrounding whitespace, an optional
/// sign, and digits optionally separated by single underscores.
fn py_int(s : String) -> Int raise HandleError {
  let s = py_strip(s)
  let n = s.length()
  let mut i = 0
  let mut neg = false
  if i < n && (s[i] == '+' || s[i] == '-') {
    neg = s[i] == '-'
    i += 1
  }
  if i >= n {
    raise InvalidValue
  }
  let mut acc = 0L
  let mut prev_digit = false
  while i < n {
    let c = s[i]
    if c >= '0' && c <= '9' {
      acc = acc * 10L + (c.to_int() - '0').to_int64()
      if acc > 2147483648L {
        // beyond Int range (Python ints are unbounded)
        raise InvalidValue
      }
      prev_digit = true
    } else if c == '_' &&
      prev_digit &&
      i + 1 < n &&
      s[i + 1] >= '0' &&
      s[i + 1] <= '9' {
      prev_digit = false
    } else {
      raise InvalidValue
    }
    i += 1
  }
  let v = if neg { -acc } else { acc }
  if v > 2147483647L {
    raise InvalidValue
  }
  v.to_int()
}
