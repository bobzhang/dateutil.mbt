// TZif decoder (RFC 9636; versions 1 to 4). For version 2+ files the
// 64-bit second data block is used together with the footer TZ string,
// which describes local time after the last transition. Leap-second
// records are skipped (local time is computed as for POSIX `time_t`).

///|
/// A local time type: offset in seconds *east* of UTC, DST flag and
/// abbreviation.
pub(all) struct TimeType {
  offset : Int
  isdst : Bool
  abbr : String
} derive(Eq, Debug)

///|
/// Decoded TZif data.
pub(all) struct Tzif {
  /// 1 for version-1 files (`'\0'`), otherwise 2, 3, 4, ...
  version : Int
  /// Transition times (seconds since the epoch, UTC), ascending.
  transitions : Array[Int64]
  /// For each transition, the index into `types` that applies from it.
  type_indices : Array[Int]
  types : Array[TimeType]
  /// Footer TZ string (version 2+; empty if absent).
  footer_text : String
  /// The footer parsed as a POSIX TZ string (`None` if empty or invalid).
  footer : PosixTz?
} derive(Eq, Debug)

///|
/// Malformed zone data.
pub(all) suberror TzdataError {
  InvalidTzif(String)
} derive(Eq, Debug)

///|
priv struct Reader {
  data : BytesView
  mut pos : Int
}

///|
fn Reader::need(self : Reader, n : Int) -> Unit raise TzdataError {
  if n < 0 || n > self.data.length() - self.pos {
    raise InvalidTzif("unexpected end of data")
  }
}

///|
fn Reader::u8(self : Reader) -> Int raise TzdataError {
  self.need(1)
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
fn Reader::i32(self : Reader) -> Int raise TzdataError {
  self.need(4)
  let d = self.data
  let p = self.pos
  self.pos += 4
  (d[p].to_int() << 24) |
  (d[p + 1].to_int() << 16) |
  (d[p + 2].to_int() << 8) |
  d[p + 3].to_int()
}

///|
fn Reader::i64(self : Reader) -> Int64 raise TzdataError {
  let hi = self.i32().to_int64()
  let lo = self.i32().reinterpret_as_uint().to_uint64().reinterpret_as_int64()
  (hi << 32) | lo
}

///|
fn Reader::skip(self : Reader, n : Int) -> Unit raise TzdataError {
  self.need(n)
  self.pos += n
}

///|
/// Upper bound for every TZif count (real files have a few thousand
/// entries at most).
let max_count : Int = 0x100000

///|
priv struct Header {
  version : Int
  isutcnt : Int
  isstdcnt : Int
  leapcnt : Int
  timecnt : Int
  typecnt : Int
  charcnt : Int
}

///|
fn Reader::header(self : Reader) -> Header raise TzdataError {
  if self.pos + 4 > self.data.length() ||
    self.u8() != 'T' ||
    self.u8() != 'Z' ||
    self.u8() != 'i' ||
    self.u8() != 'f' {
    raise InvalidTzif("bad magic")
  }
  self.need(40)
  let v = self.u8()
  let version = if v == 0 {
    1
  } else if v >= '2' && v <= '9' {
    v - '0'
  } else {
    raise InvalidTzif("unsupported version")
  }
  self.skip(15)
  let isutcnt = self.i32()
  let isstdcnt = self.i32()
  let leapcnt = self.i32()
  let timecnt = self.i32()
  let typecnt = self.i32()
  let charcnt = self.i32()
  if isutcnt < 0 ||
    isstdcnt < 0 ||
    leapcnt < 0 ||
    timecnt < 0 ||
    typecnt <= 0 ||
    typecnt > 256 ||
    charcnt <= 0 {
    raise InvalidTzif("bad counts")
  }
  // Each count is bounded by the data size (and by `max_count`), so the
  // block-size arithmetic below cannot overflow.
  for c in [isutcnt, isstdcnt, leapcnt, timecnt, charcnt] {
    if c > max_count || c > self.data.length() {
      raise InvalidTzif("bad counts")
    }
  }
  { version, isutcnt, isstdcnt, leapcnt, timecnt, typecnt, charcnt, }
}

///|
/// Decode one data block with `time_size`-byte transition times.
fn Reader::block(
  self : Reader,
  h : Header,
  time_size : Int,
) -> (Array[Int64], Array[Int], Array[TimeType]) raise TzdataError {
  self.need(
    h.timecnt * (time_size + 1) +
    h.typecnt * 6 +
    h.charcnt +
    h.leapcnt * (time_size + 4) +
    h.isstdcnt +
    h.isutcnt,
  )
  let transitions = Array(capacity=h.timecnt)
  for _ in 0..<h.timecnt {
    transitions.push(
      if time_size == 8 {
        self.i64()
      } else {
        self.i32().to_int64()
      },
    )
  }
  let type_indices = Array(capacity=h.timecnt)
  for _ in 0..<h.timecnt {
    let idx = self.u8()
    if idx >= h.typecnt {
      raise InvalidTzif("transition type index out of range")
    }
    type_indices.push(idx)
  }
  let raw_types = Array(capacity=h.typecnt)
  for _ in 0..<h.typecnt {
    let offset = self.i32()
    let isdst = self.u8()
    let desig = self.u8()
    if isdst > 1 || desig >= h.charcnt {
      raise InvalidTzif("bad local time type")
    }
    raw_types.push((offset, isdst == 1, desig))
  }
  let chars = self.data[self.pos:self.pos + h.charcnt]
  self.pos += h.charcnt
  let types = raw_types.map(rt => {
    let (offset, isdst, desig) = rt
    let abbr = StringBuilder()
    for i in desig..<chars.length() {
      let b = chars[i]
      if b == 0 {
        break
      }
      abbr.write_char(b.to_int().unsafe_to_char())
    }
    { offset, isdst, abbr: abbr.to_string(), }
  })
  self.skip(h.leapcnt * (time_size + 4) + h.isstdcnt + h.isutcnt)
  (transitions, type_indices, types)
}

///|
/// Decode TZif data (any version).
///
/// ```mbt check
/// test {
///   try @tzdata.parse_tzif(b"not a zone") catch {
///     err => debug_inspect(err, content="InvalidTzif(\"bad magic\")")
///   } noraise {
///     _ => fail("expected an error")
///   }
/// }
/// ```
pub fn parse_tzif(data : BytesView) -> Tzif raise TzdataError {
  let r = Reader::{ data, pos: 0, }
  let h1 = r.header()
  if h1.version == 1 {
    let (transitions, type_indices, types) = r.block(h1, 4)
    return {
      version: 1,
      transitions,
      type_indices,
      types,
      footer_text: "",
      footer: None,
    }
  }
  // Skip the 32-bit block and use the 64-bit one.
  r.skip(
    h1.timecnt * 5 +
    h1.typecnt * 6 +
    h1.charcnt +
    h1.leapcnt * 8 +
    h1.isstdcnt +
    h1.isutcnt,
  )
  let h2 = r.header()
  let (transitions, type_indices, types) = r.block(h2, 8)
  // Footer: "\n" TZ-string "\n".
  let mut footer_text = ""
  if r.pos < data.length() && data[r.pos] == b'\n' {
    let start = r.pos + 1
    let mut end = start
    while end < data.length() && data[end] != b'\n' {
      end += 1
    }
    let sb = StringBuilder()
    for i in start..<end {
      sb.write_char(data[i].to_int().unsafe_to_char())
    }
    footer_text = sb.to_string()
  }
  let footer = if footer_text == "" {
    None
  } else {
    parse_posix_tz(footer_text)
  }
  {
    version: h2.version,
    transitions,
    type_indices,
    types,
    footer_text,
    footer,
  }
}

///|
/// glibc / zoneinfo: before the first transition, the first standard-time
/// type applies (type 0 if every type is DST).
fn Tzif::type_before(self : Tzif) -> TimeType {
  for ty in self.types {
    if !ty.isdst {
      return ty
    }
  }
  self.types[0]
}

///|
/// The local time type in effect at `t` (seconds since the epoch, UTC).
pub fn Tzif::lookup(self : Tzif, t : Int64) -> TimeType {
  let n = self.transitions.length()
  if n == 0 {
    return match self.footer {
      Some(f) => f.lookup(t)
      None => self.type_before()
    }
  }
  if t < self.transitions[0] {
    return self.type_before()
  }
  // last index i with transitions[i] <= t
  let i = for lo = 0, hi = n; hi - lo > 1; {
    let mid = lo + (hi - lo) / 2
    if self.transitions[mid] <= t {
      continue mid, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo
  }
  if i == n - 1 && self.footer is Some(f) {
    f.lookup(t)
  } else {
    self.types[self.type_indices[i]]
  }
}
