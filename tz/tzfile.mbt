// dateutil `tzfile`: time zones read from TZif (`tzfile(5)`) data.

///|
/// dateutil `_ttinfo`: one local time type. `dstoffset` is mutable because
/// dateutil fills it in while walking the transitions, and the objects are
/// shared between `ttinfo_list` and `trans_idx`.
priv struct TtInfo {
  offset : Int
  delta : @datetime.TimeDelta
  isdst : Int
  abbr : String
  isstd : Bool
  isgmt : Bool
  mut dstoffset : @datetime.TimeDelta
}

///|
/// Python `_ttinfo.__eq__` compares all fields; this is the canonical text
/// of those fields, used for the zone fingerprint.
fn TtInfo::value_key(self : TtInfo) -> String {
  "\{self.offset},\{self.isdst},\{@datetime.py_str_repr(self.abbr)},\{self.isstd},\{self.isgmt},\{self.dstoffset.repr()}"
}

///|
/// dateutil `_tzfile`: the transition data read from a TZif file.
priv struct TzFileData {
  /// Transition times in UTC (seconds since the epoch).
  trans_list_utc : Array[Int64]
  /// Transition times in "wall" time, as computed by dateutil.
  trans_list : Array[Int64]
  /// The local time type in effect after each transition.
  trans_idx : Array[TtInfo]
  ttinfo_list : Array[TtInfo]
  ttinfo_std : TtInfo?
  ttinfo_dst : TtInfo?
  ttinfo_before : TtInfo?
}

///|
/// A cursor over the TZif bytes, mirroring the reads `_read_tzfile` makes.
priv struct ByteReader {
  data : BytesView
  mut pos : Int
}

///|
fn ByteReader::take(
  self : ByteReader,
  n : Int,
) -> BytesView raise @datetime.DateTimeError {
  if n < 0 || self.pos + n > self.data.length() {
    raise @datetime.ValueError("tzfile: unexpected end of data")
  }
  let v = self.data[self.pos:self.pos + n]
  self.pos += n
  v
}

///|
/// A big-endian signed 32-bit integer (`struct` format `>l`).
fn ByteReader::read_i32(self : ByteReader) -> Int raise @datetime.DateTimeError {
  let b = self.take(4)
  (b[0].to_int() << 24) |
  (b[1].to_int() << 16) |
  (b[2].to_int() << 8) |
  b[3].to_int()
}

///|
/// A signed byte (`struct` format `b`).
fn ByteReader::read_i8(self : ByteReader) -> Int raise @datetime.DateTimeError {
  let v = self.take(1)[0].to_int()
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
/// An unsigned byte (`struct` format `B`).
fn ByteReader::read_u8(self : ByteReader) -> Int raise @datetime.DateTimeError {
  self.take(1)[0].to_int()
}

///|
/// Python `s.find(sub, start)` for a single character, with Python's
/// handling of negative and out-of-range `start`.
fn py_find_char(s : String, c : Char, start : Int) -> Int {
  let len = s.length()
  let start = if start < 0 {
    let st = start + len
    if st < 0 {
      0
    } else {
      st
    }
  } else {
    start
  }
  for i in start..<len {
    if s.get_char(i) is Some(ch) && ch == c {
      return i
    }
  }
  -1
}

///|
/// Python `s[start:end]` with Python's clamping of negative and
/// out-of-range indices.
fn py_slice(s : String, start : Int, end : Int) -> String {
  let len = s.length()
  fn norm(i : Int) -> Int {
    if i < 0 {
      let j = i + len
      if j < 0 {
        0
      } else {
        j
      }
    } else if i > len {
      len
    } else {
      i
    }
  }
  let a = norm(start)
  let b = norm(end)
  if a >= b {
    ""
  } else {
    s.view(start_offset=a, end_offset=b).to_owned()
  }
}

///|
/// dateutil `tzfile._read_tzfile`. Like dateutil, only the version 1
/// (32-bit) header and data block are read, whatever the file version.
/// Returns the data and the number of bytes consumed.
fn read_tzfile(
  data : BytesView,
) -> (TzFileData, Int) raise @datetime.DateTimeError {
  let r = ByteReader::{ data, pos: 0, }
  // magic
  let magic = if data.length() >= 4 { data[0:4] } else { data[:] }
  r.pos = magic.length()
  if magic.to_owned() != b"TZif" {
    raise @datetime.ValueError("magic not found")
  }
  // sixteen bytes reserved for future use (the version byte is the first)
  ignore(r.take(16))
  let ttisgmtcnt = r.read_i32()
  let ttisstdcnt = r.read_i32()
  let leapcnt = r.read_i32()
  let timecnt = r.read_i32()
  let typecnt = r.read_i32()
  let charcnt = r.read_i32()
  if ttisgmtcnt < 0 ||
    ttisstdcnt < 0 ||
    leapcnt < 0 ||
    timecnt < 0 ||
    typecnt < 0 ||
    charcnt < 0 {
    raise @datetime.ValueError("tzfile: negative count in header")
  }
  let trans_list_utc : Array[Int64] = []
  for _ in 0..<timecnt {
    trans_list_utc.push(r.read_i32().to_int64())
  }
  let trans_idx_raw : Array[Int] = []
  for _ in 0..<timecnt {
    trans_idx_raw.push(r.read_u8())
  }
  let ttinfo_raw : Array[(Int, Int, Int)] = []
  for _ in 0..<typecnt {
    let gmtoff = r.read_i32()
    let isdst = r.read_i8()
    let abbrind = r.read_i8()
    ttinfo_raw.push((gmtoff, isdst, abbrind))
  }
  let abbr = @utf8.decode(r.take(charcnt)) catch {
    _ => raise @datetime.ValueError("tzfile: invalid abbreviation data")
  }
  // Leap second records are not used (but are skipped over).
  ignore(r.take(leapcnt * 8))
  let isstd : Array[Int] = []
  for _ in 0..<ttisstdcnt {
    isstd.push(r.read_i8())
  }
  let isgmt : Array[Int] = []
  for _ in 0..<ttisgmtcnt {
    isgmt.push(r.read_i8())
  }
  // Build ttinfo list
  let ttinfo_list : Array[TtInfo] = []
  for i, raw in ttinfo_raw {
    let (gmtoff, isdst, abbrind) = raw
    ttinfo_list.push({
      offset: gmtoff,
      dstoffset: @datetime.zero_timedelta,
      delta: @datetime.TimeDelta::try_new(seconds=gmtoff),
      isdst,
      abbr: py_slice(abbr, abbrind, py_find_char(abbr, '\u{0}', abbrind)),
      isstd: ttisstdcnt > i && isstd[i] != 0,
      isgmt: ttisgmtcnt > i && isgmt[i] != 0,
    })
  }
  // Replace ttinfo indexes for ttinfo objects.
  let trans_idx : Array[TtInfo] = []
  for idx in trans_idx_raw {
    guard ttinfo_list.get(idx) is Some(tti) else {
      raise @datetime.ValueError("tzfile: transition type index out of range")
    }
    trans_idx.push(tti)
  }
  // Set standard, dst, and before ttinfos. before will be used when a
  // given time is before any transitions, and will be set to the first
  // non-dst ttinfo, or to the first dst, if all of them are dst.
  let mut ttinfo_std : TtInfo? = None
  let mut ttinfo_dst : TtInfo? = None
  let mut ttinfo_before : TtInfo? = None
  if ttinfo_list.length() > 0 {
    if trans_list_utc.length() == 0 {
      ttinfo_std = Some(ttinfo_list[0])
    } else {
      let mut broke = false
      for i = timecnt - 1; i >= 0; i = i - 1 {
        let tti = trans_idx[i]
        if ttinfo_std is None && tti.isdst == 0 {
          ttinfo_std = Some(tti)
        } else if ttinfo_dst is None && tti.isdst != 0 {
          ttinfo_dst = Some(tti)
        }
        if ttinfo_std is Some(_) && ttinfo_dst is Some(_) {
          broke = true
          break
        }
      }
      if !broke && ttinfo_dst is Some(_) && ttinfo_std is None {
        ttinfo_std = ttinfo_dst
      }
      for tti in ttinfo_list {
        if tti.isdst == 0 {
          ttinfo_before = Some(tti)
          break
        }
      } nobreak {
        ttinfo_before = Some(ttinfo_list[0])
      }
    }
  }
  // Now fix transition times to become relative to wall time.
  let mut lastdst : Int? = None
  let mut lastoffset = 0
  let mut lastdstoffset : Int? = None
  let mut lastbaseoffset : Int? = None
  let trans_list : Array[Int64] = []
  for i, tti in trans_idx {
    let offset = tti.offset
    let mut dstoffset = 0
    if lastdst is Some(ld) {
      if tti.isdst != 0 {
        if ld == 0 {
          dstoffset = offset - lastoffset
        }
        if dstoffset == 0 && lastdstoffset is Some(ldo) && ldo != 0 {
          dstoffset = ldo
        }
        tti.dstoffset = @datetime.TimeDelta::try_new(seconds=dstoffset)
        lastdstoffset = Some(dstoffset)
      }
    }
    // If a time zone changes its base offset during a DST transition,
    // then you need to adjust by the previous base offset to get the
    // transition time in local time. Otherwise you use the current base
    // offset.
    let baseoffset = offset - dstoffset
    let mut adjustment = baseoffset
    if lastbaseoffset is Some(lbo) &&
      baseoffset != lbo &&
      Some(tti.isdst) != lastdst {
      // The base DST has changed
      adjustment = lbo
    }
    lastdst = Some(tti.isdst)
    lastoffset = offset
    lastbaseoffset = Some(baseoffset)
    trans_list.push(trans_list_utc[i] + adjustment.to_int64())
  }
  let out = {
    trans_list_utc,
    trans_list,
    trans_idx,
    ttinfo_list,
    ttinfo_std,
    ttinfo_dst,
    ttinfo_before,
  }
  (out, r.pos)
}

///|
/// The fingerprint behind `tzfile.__eq__`: equal transition lists, equal
/// (by value) transition types and equal type lists.
fn TzFileData::eq_key(self : TzFileData) -> String {
  let buf = StringBuilder()
  buf.write_string("dateutil.tzfile:")
  for t in self.trans_list {
    buf.write_string(t.to_string())
    buf.write_char(',')
  }
  buf.write_char('|')
  let keys = self.ttinfo_list.map(t => t.value_key())
  for k in keys {
    buf.write_string(k)
    buf.write_char(';')
  }
  buf.write_char('|')
  // Every transition type is an element of `ttinfo_list`; encode it by
  // the first index of an equal value so that equal-by-value lists give
  // equal keys.
  for tti in self.trans_idx {
    let k = tti.value_key()
    let idx = keys.search(k).unwrap_or(-1)
    buf.write_string(idx.to_string())
    buf.write_char(',')
  }
  buf.to_string()
}

///|
priv struct TzFile {
  filename : String
  data : TzFileData
  key : String
}

///|
/// `bisect.bisect_right(trans_list, timestamp) - 1`, or `None` when there
/// are no transitions (dateutil `_find_last_transition`).
fn TzFile::find_last_transition(
  self : TzFile,
  dt : @datetime.DateTime,
  in_utc? : Bool = false,
) -> Int? {
  let list = if in_utc {
    self.data.trans_list_utc
  } else {
    self.data.trans_list
  }
  if self.data.trans_list.length() == 0 {
    return None
  }
  let ts = naive_timestamp_us(dt)
  // bisect_right: first index whose element is > ts
  let mut lo = 0
  let mut hi = list.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if ts < list[mid] * 1000000L {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  Some(lo - 1)
}

///|
/// dateutil `_get_ttinfo`: after the last transition (and with no
/// transitions) the standard type is used; before the first, `before`.
fn TzFile::get_ttinfo(self : TzFile, idx : Int?) -> TtInfo? {
  match idx {
    None => self.data.ttinfo_std
    Some(i) =>
      if i + 1 >= self.data.trans_list.length() {
        self.data.ttinfo_std
      } else if i < 0 {
        self.data.ttinfo_before
      } else {
        Some(self.data.trans_idx[i])
      }
  }
}

///|
/// dateutil `tzfile.is_ambiguous(dt, idx)`.
fn TzFile::is_ambiguous_idx(
  self : TzFile,
  dt : @datetime.DateTime,
  idx : Int?,
) -> Bool {
  let idx = match idx {
    None => self.find_last_transition(dt)
    Some(_) => idx
  }
  let timestamp = naive_timestamp_us(dt)
  let tti = self.get_ttinfo(idx)
  guard idx is Some(i) && i > 0 else { return false }
  let prev_offset = match self.get_ttinfo(Some(i - 1)) {
    Some(p) => p.offset
    None => 0
  }
  let cur_offset = match tti {
    Some(t) => t.offset
    None => 0
  }
  let od = prev_offset - cur_offset
  let tt = self.data.trans_list[i] // Transition time
  timestamp < (tt + od.to_int64()) * 1000000L
}

///|
/// dateutil `_resolve_ambiguous_time`.
fn TzFile::resolve_ambiguous_time(
  self : TzFile,
  dt : @datetime.DateTime,
) -> Int? {
  let idx = self.find_last_transition(dt)
  match idx {
    None | Some(0) => idx
    Some(i) => {
      // If it's ambiguous and we're in a fold, shift to a different index.
      let idx_offset = if dt.fold == 0 && self.is_ambiguous_idx(dt, idx) {
        1
      } else {
        0
      }
      Some(i - idx_offset)
    }
  }
}

///|
fn TzFile::find_ttinfo(self : TzFile, dt : @datetime.DateTime) -> TtInfo? {
  self.get_ttinfo(self.resolve_ambiguous_time(dt))
}

///|
impl @datetime.TzInfo for TzFile with fn utcoffset(self, dt) {
  guard dt is Some(dt) else { return None }
  if self.data.ttinfo_std is None {
    return Some(@datetime.zero_timedelta)
  }
  match self.find_ttinfo(dt) {
    Some(tti) => Some(tti.delta)
    None => Some(@datetime.zero_timedelta)
  }
}

///|
impl @datetime.TzInfo for TzFile with fn dst(self, dt) {
  guard dt is Some(dt) else { return None }
  if self.data.ttinfo_dst is None {
    return Some(@datetime.zero_timedelta)
  }
  match self.find_ttinfo(dt) {
    Some(tti) if tti.isdst != 0 =>
      // The documentation says that utcoffset()-dst() must be constant
      // for every dt.
      Some(tti.dstoffset)
    _ => Some(@datetime.zero_timedelta)
  }
}

///|
impl @datetime.TzInfo for TzFile with fn tzname(self, dt) {
  guard dt is Some(dt) && self.data.ttinfo_std is Some(_) else { return None }
  self.find_ttinfo(dt).map(t => t.abbr)
}

///|
/// The `tzfile` implementation of `fromutc`: treat UTC as wall time to
/// find the transition, then decide the fold from it.
impl @datetime.TzInfo for TzFile with fn fromutc(self, dt) {
  // First treat UTC as wall time and get the transition we're in.
  let idx = self.find_last_transition(dt, in_utc=true)
  let offset = match self.get_ttinfo(idx) {
    Some(tti) => tti.offset
    None => 0
  }
  let dt_out = dt.add(@datetime.TimeDelta::try_new(seconds=offset))
  let fold = self.is_ambiguous_idx(dt_out, idx)
  enfold(dt_out, fold=if fold { 1 } else { 0 })
}

///|
impl @datetime.TzInfo for TzFile with fn is_ambiguous(self, dt) {
  Some(self.is_ambiguous_idx(dt, None))
}

///|
impl @datetime.TzInfo for TzFile with fn repr(self) {
  "tzfile(\{@datetime.py_str_repr(self.filename)})"
}

///|
impl @datetime.TzInfo for TzFile with fn eq_key(self) {
  Some(self.key)
}

///|
fn TzFile::new(data : TzFileData, filename : String) -> TzFile {
  { filename, data, key: data.eq_key(), }
}

///|
/// `tzfile(fileobj, filename)` for in-memory TZif data (version 1, 2 or
/// 3; like dateutil, only the 32-bit version 1 block is used).
/// `filename` only affects `repr()`; Python would default it to the file
/// object's `name` (or its `repr()`), here it defaults to `"<bytes>"`.
/// Raises `ValueError` for malformed data. Each call returns a new zone.
///
/// ```mbt check
/// test {
///   let bad = try? @tz.tzfile_from_bytes(b"BadFile")
///   assert_true(bad is Err(_))
/// }
/// ```
pub fn tzfile_from_bytes(
  data : BytesView,
  filename? : String = "<bytes>",
) -> @datetime.Tz raise @datetime.DateTimeError {
  let (parsed, _) = read_tzfile(data)
  @datetime.Tz::new(TzFile::new(parsed, filename))
}

///|
/// `tzfile(path)`: read a TZif file from the file system. The `repr()` is
/// `tzfile('<path>')`. Raises `IOError` if the file cannot be read (or the
/// backend has no file system) and `@datetime.ValueError` if it is not a
/// valid TZif file.
pub fn tzfile(path : String) -> @datetime.Tz raise {
  let data = read_file_bytes(path)
  tzfile_from_bytes(data, filename=path)
}
