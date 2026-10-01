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
/// First code points of the Unicode (15.1) decimal digit runs (category Nd,
/// each run is `zero..=zero+9`).
let decimal_zeros : FixedArray[Int] = [
  0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66, 0xce6,
  0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0,
  0x1a80, 0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0,
  0xa9f0, 0xaa50, 0xabf0, 0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0,
  0x112f0, 0x11450, 0x114d0, 0x11650, 0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50,
  0x11d50, 0x11da0, 0x11f50, 0x16a60, 0x16ac0, 0x16b50, 0x1d7ce, 0x1d7d8, 0x1d7e2,
  0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e4f0, 0x1e950, 0x1fbf0,
]

///|
/// Python `unicodedata.decimal(c)`.
fn decimal_value(c : Char) -> Int? {
  let c = c.to_int()
  for z in decimal_zeros {
    if c >= z && c <= z + 9 {
      return Some(c - z)
    }
  }
  None
}

///|
/// Python `int(s)` for base-10 strings: surrounding whitespace, an optional
/// sign, and (Unicode) decimal digits optionally separated by single
/// underscores. Values must fit in `Int` (Python ints are unbounded).
fn py_int(s : String) -> Int raise HandleError {
  let chars = py_strip(s).to_array()
  let n = chars.length()
  let mut i = 0
  let mut neg = false
  if i < n && (chars[i] == '+' || chars[i] == '-') {
    neg = chars[i] == '-'
    i += 1
  }
  if i >= n {
    raise InvalidValue
  }
  let mut acc = 0L
  let mut prev_digit = false
  while i < n {
    match decimal_value(chars[i]) {
      Some(d) => {
        acc = acc * 10L + d.to_int64()
        if acc > 2147483648L {
          raise InvalidValue
        }
        prev_digit = true
      }
      None =>
        if chars[i] == '_' &&
          prev_digit &&
          i + 1 < n &&
          decimal_value(chars[i + 1]) is Some(_) {
          prev_digit = false
        } else {
          raise InvalidValue
        }
    }
    i += 1
  }
  let v = if neg { -acc } else { acc }
  if v > 2147483647L {
    raise InvalidValue
  }
  v.to_int()
}
