// Small Python `str` helpers needed by the iCalendar reader.

///|
/// Python `str.isspace()` for one character.
fn py_isspace(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0d | 0x1c..=0x20 | 0x85 | 0xa0 | 0x1680 | 0x2000..=0x200a => true
    0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 => true
    _ => false
  }
}

///|
fn py_rstrip(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && py_isspace(chars[end - 1]) {
    end -= 1
  }
  String::from_array(chars[:end])
}

///|
fn py_strip(s : String) -> String {
  let chars = py_rstrip(s).to_array()
  let mut start = 0
  while start < chars.length() && py_isspace(chars[start]) {
    start += 1
  }
  String::from_array(chars[start:])
}

///|
/// Python `str.splitlines()` (without keepends).
fn py_splitlines(s : String) -> Array[String] {
  let out = []
  let buf = StringBuilder()
  let chars = s.to_array()
  let n = chars.length()
  let mut i = 0
  let mut pending = false
  while i < n {
    let c = chars[i]
    match c.to_int() {
      0x0a | 0x0b | 0x0c | 0x1c | 0x1d | 0x1e | 0x85 | 0x2028 | 0x2029 => {
        out.push(buf.to_string())
        buf.reset()
        pending = false
      }
      0x0d => {
        out.push(buf.to_string())
        buf.reset()
        pending = false
        if i + 1 < n && chars[i + 1] == '\n' {
          i += 1
        }
      }
      _ => {
        buf.write_char(c)
        pending = true
      }
    }
    i += 1
  }
  if pending {
    out.push(buf.to_string())
  }
  out
}

///|
fn ascii_upper(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    buf.write_char(
      if c >= 'a' && c <= 'z' {
        (c.to_int() - 32).unsafe_to_char()
      } else {
        c
      },
    )
  }
  buf.to_string()
}
