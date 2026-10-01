///|
fn posix(s : String) -> @tzdata.Zone raise {
  guard @tzdata.parse_posix_tz(s) is Some(p) else { fail("cannot parse \{s}") }
  PosixZone(p)
}

///|
/// Seconds since the epoch of a UTC civil time.
fn utc(y : Int, m : Int, d : Int, h? : Int = 0, mi? : Int = 0) -> Int64 {
  @tzdata.days_from_civil(y.to_int64(), m, d) * 86400L +
  (h * 3600 + mi * 60).to_int64()
}

///|
test "calendar round trip" {
  for days in [-1000000L, -719162L, -1L, 0L, 59L, 11016L, 2932896L] {
    let (y, m, d) = @tzdata.civil_from_days(days)
    assert_eq(@tzdata.days_from_civil(y, m, d), days)
  }
  // 2024-01-01 was a Monday
  inspect(
    @tzdata.weekday_from_days(@tzdata.days_from_civil(2024, 1, 1)),
    content="1",
  )
  assert_true(@tzdata.is_leap(2000) && !@tzdata.is_leap(1900))
}

///|
test "parse_posix_tz: accepted strings" {
  debug_inspect(
    @tzdata.parse_posix_tz("EST5EDT"),
    content=(
      #|Some(
      #|  {
      #|    std_abbr: "EST",
      #|    std_offset: -18000,
      #|    dst: Some(
      #|      {
      #|        abbr: "EDT",
      #|        offset: -14400,
      #|        start: { date: MonthWeekDay(month=3, week=2, weekday=0), time: 7200 },
      #|        end: { date: MonthWeekDay(month=11, week=1, weekday=0), time: 7200 },
      #|      },
      #|    ),
      #|  },
      #|)
    ),
  )
  debug_inspect(
    @tzdata.parse_posix_tz("<-03>3<-02>,J60/-2:30,300/26:00:01"),
    content=(
      #|Some(
      #|  {
      #|    std_abbr: "-03",
      #|    std_offset: -10800,
      #|    dst: Some(
      #|      {
      #|        abbr: "-02",
      #|        offset: -7200,
      #|        start: { date: Julian1(60), time: -9000 },
      #|        end: { date: Julian0(300), time: 93601 },
      #|      },
      #|    ),
      #|  },
      #|)
    ),
  )
  debug_inspect(
    @tzdata.parse_posix_tz("WART4WARST3,J1/0,J365/25"),
    content=(
      #|Some(
      #|  {
      #|    std_abbr: "WART",
      #|    std_offset: -14400,
      #|    dst: Some(
      #|      {
      #|        abbr: "WARST",
      #|        offset: -10800,
      #|        start: { date: Julian1(1), time: 0 },
      #|        end: { date: Julian1(365), time: 90000 },
      #|      },
      #|    ),
      #|  },
      #|)
    ),
  )
  debug_inspect(
    @tzdata.parse_posix_tz("JST-9"),
    content=(
      #|Some({ std_abbr: "JST", std_offset: 32400, dst: None })
    ),
  )
  debug_inspect(
    @tzdata.parse_posix_tz("<+0545>-05:45:00"),
    content=(
      #|Some({ std_abbr: "+0545", std_offset: 20700, dst: None })
    ),
  )
}

///|
test "parse_posix_tz: rejected strings" {
  for
    s in [
      "", "UTC", "EST", "AB5", "<AB>5", "<EST5", "EST+", "EST25", "EST5:60", "EST5EDT,M3.2.0",
      "EST5EDT,M13.1.0,M11.1.0", "EST5EDT,M3.6.0,M11.1.0", "EST5EDT,M3.2.7,M11.1.0",
      "EST5EDT,J0,J365", "EST5EDT,366,0", "EST5,M3.2.0,M11.1.0", "EST5EDT,M3.2.0/168,M11.1.0",
      "EST5EDT,M3.2.0,M11.1.0,", "EST5EDT4x", "Europe/London", ":EST5", "EST 5",
    ] {
    if @tzdata.parse_posix_tz(s) is Some(p) {
      fail("accepted \{s}: \{Repr(p)}")
    }
  }
}

///|
test "POSIX: DST without rules uses M3.2.0,M11.1.0 (glibc)" {
  let z = posix("AAA3BBB")
  inspect(z.lookup(utc(2024, 7, 1)).abbr, content="BBB")
  inspect(z.lookup(utc(2024, 7, 1)).offset, content="-7200")
  inspect(z.lookup(utc(2024, 1, 1)).abbr, content="AAA")
  // 2024-03-10 02:00 AAA = 05:00 UTC
  inspect(z.lookup(utc(2024, 3, 10, h=4, mi=59)).abbr, content="AAA")
  inspect(z.lookup(utc(2024, 3, 10, h=5)).abbr, content="BBB")
}

///|
test "POSIX: all-year DST (RFC 9636 examples)" {
  // EST5EDT,0/0,J365/25: DST all year, 4 hours behind UT
  let z = posix("EST5EDT,0/0,J365/25")
  for
    t in [
      utc(2023, 12, 31, h=23),
      utc(2024, 1, 1),
      utc(2024, 1, 1, h=4, mi=59),
      utc(2024, 1, 1, h=5),
      utc(2024, 7, 1),
      utc(1600, 1, 1, h=2),
      utc(2400, 12, 31, h=23),
    ] {
    let ty = z.lookup(t)
    assert_true(ty.isdst && ty.offset == -14400, msg="EDT at \{t}")
  }
  // Africa/Casablanca's footer: permanent (negative) DST at +01
  let z = posix("XXX-2<+01>-1,0/0,J365/23")
  for
    t in [
      utc(2090, 1, 1),
      utc(2089, 12, 31, h=22),
      utc(2089, 12, 31, h=23),
      utc(2090, 6, 1),
    ] {
    debug_inspect(
      z.lookup(t),
      content=(
        #|{ offset: 3600, isdst: true, abbr: "+01" }
      ),
    )
  }
}

///|
test "POSIX: extreme timestamps" {
  let z = posix("AEST-10AEDT,M10.1.0,M4.1.0/3")
  // any Int64 is accepted; the rules repeat every 400 years
  ignore(z.lookup(9223372036854775807L))
  ignore(z.lookup(-9223372036854775807L - 1L))
  let cycle = 146097L * 86400L
  for t in [utc(2024, 1, 15), utc(2024, 7, 15), utc(2024, 4, 7, h=15, mi=59)] {
    assert_eq(z.lookup(t), z.lookup(t + 1000L * cycle))
    assert_eq(z.lookup(t), z.lookup(t - 1000L * cycle))
  }
}

///|
test "TZif: Europe/London 1941 (BST in winter) and the footer era" {
  let z = zone_from_corpus("Europe/London")
  debug_inspect(
    z.lookup(utc(1941, 1, 15, h=12)),
    content=(
      #|{ offset: 3600, isdst: true, abbr: "BST" }
    ),
  )
  debug_inspect(
    z.lookup(utc(1941, 7, 15, h=12)),
    content=(
      #|{ offset: 7200, isdst: true, abbr: "BDST" }
    ),
  )
  debug_inspect(
    z.lookup(utc(2024, 7, 1, h=12)),
    content=(
      #|{ offset: 3600, isdst: true, abbr: "BST" }
    ),
  )
  debug_inspect(
    z.lookup(utc(2500, 1, 1)),
    content=(
      #|{ offset: 0, isdst: false, abbr: "GMT" }
    ),
  )
  // before the first transition: local mean time
  debug_inspect(
    z.lookup(utc(1800, 1, 1)),
    content=(
      #|{ offset: -75, isdst: false, abbr: "LMT" }
    ),
  )
  ignore(z.lookup(9223372036854775807L))
  ignore(z.lookup(-9223372036854775807L - 1L))
}

///|
test "TZif: sub-minute offsets, footer, southern hemisphere" {
  let paris = zone_from_corpus("Europe/Paris")
  debug_inspect(
    paris.lookup(utc(1900, 1, 1)),
    content=(
      #|{ offset: 561, isdst: false, abbr: "PMT" }
    ),
  )
  let ny = zone_from_corpus("America/New_York")
  debug_inspect(
    ny.lookup(utc(2040, 7, 1)),
    content=(
      #|{ offset: -14400, isdst: true, abbr: "EDT" }
    ),
  )
  let syd = zone_from_corpus("Australia/Sydney")
  debug_inspect(
    syd.lookup(utc(2050, 1, 1)),
    content=(
      #|{ offset: 39600, isdst: true, abbr: "AEDT" }
    ),
  )
  debug_inspect(
    syd.lookup(utc(2050, 7, 1)),
    content=(
      #|{ offset: 36000, isdst: false, abbr: "AEST" }
    ),
  )
}

///|
test "TZif: header fields and footer" {
  guard zone_from_corpus("America/New_York") is TzifZone(z) else { fail("") }
  inspect(z.version, content="2")
  inspect(z.footer_text, content="EST5EDT,M3.2.0,M11.1.0")
  assert_true(z.footer is Some(_))
  inspect(z.types.length(), content="6")
}

///|
test "TZif: version 1 file uses the 32-bit block and no footer" {
  let bytes = @base64.decode(zone_files["America/New_York"]).to_array()
  bytes[4] = b'\x00'
  let v1 = @tzdata.parse_tzif(Bytes::from_array(bytes))
  inspect(v1.version, content="1")
  inspect(v1.footer_text, content="")
  let z = @tzdata.TzifZone(v1)
  inspect(z.lookup(utc(2000, 7, 1)).abbr, content="EDT")
  // after the last transition (2037) the last type stays in effect
  inspect(z.lookup(utc(2040, 7, 1)).abbr, content="EST")
}

///|
test "TZif: huge counts are rejected, not overflowed" {
  let header : Array[Byte] = [b'T', b'Z', b'i', b'f', b'2']
  for _ in 0..<15 {
    header.push(b'\x00')
  }
  // isutcnt, isstdcnt, leapcnt, timecnt = 0; typecnt = 1; charcnt = 0x7fffffee
  for _ in 0..<16 {
    header.push(b'\x00')
  }
  for
    b in [
      b'\x00', b'\x00', b'\x00', b'\x01', b'\x7f', b'\xff', b'\xff', b'\xee',
    ] {
    header.push(b)
  }
  try @tzdata.parse_tzif(Bytes::from_array(header)) catch {
    err => debug_inspect(err, content="InvalidTzif(\"bad counts\")")
  } noraise {
    _ => fail("expected an error")
  }
  let read = (_ : String) => Some(Bytes::from_array(header))
  assert_true(@tzdata.load_tzif("/x", read) is None)
}

///|
test "POSIX: coincident transitions mean no DST (glibc)" {
  let z = posix("AAA0BBB,J100/2,J100/3")
  for t in [utc(2024, 1, 1), utc(2024, 4, 9, h=2), utc(2024, 7, 1)] {
    inspect(z.lookup(t).abbr, content="AAA")
  }
}

///|
test "TZif: malformed data" {
  let good = @base64.decode(zone_files["Europe/Paris"])
  for
    bad in [
      b"",
      b"TZif",
      good[0:40].to_owned(),
      good[0:200].to_owned(),
      b"TZiX" + good[4:].to_owned(),
    ] {
    try @tzdata.parse_tzif(bad) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed TZif of \{bad.length()} bytes")
    }
  }
}

///|
/// A fake file system for `resolve`.
fn fake_fs(files : Map[String, Bytes]) -> (String) -> Bytes? {
  path => files.get(path)
}

///|
fn describe(r : (@tzdata.Zone, @tzdata.ZoneSource)) -> String {
  let (zone, source) = r
  let jan = zone.lookup(utc(2024, 1, 15))
  let jul = zone.lookup(utc(2024, 7, 15))
  "\{Repr(source)} \{jan.abbr}\{jan.offset}/\{jul.abbr}\{jul.offset}"
}

///|
test "resolve: glibc TZ rules" {
  let london = @base64.decode(zone_files["Europe/London"])
  let sydney = @base64.decode(zone_files["Australia/Sydney"])
  let fs = fake_fs({
    "/etc/localtime": sydney,
    "/usr/share/zoneinfo/Europe/London": london,
    "/opt/zones/Europe/London": sydney,
    "/usr/share/zoneinfo/EST5EDT": b"not a TZif file",
    "/tmp/london": london,
  })
  let r = (tz : String?) => describe(@tzdata.resolve(tz, read_file=fs))
  // unset: /etc/localtime
  inspect(r(None), content="File(\"/etc/localtime\") AEDT39600/AEST36000")
  // empty: UTC
  inspect(r(Some("")), content="Fallback UTC0/UTC0")
  // zone names, with or without the colon
  inspect(
    r(Some("Europe/London")),
    content="File(\"/usr/share/zoneinfo/Europe/London\") GMT0/BST3600",
  )
  inspect(
    r(Some(":Europe/London")),
    content="File(\"/usr/share/zoneinfo/Europe/London\") GMT0/BST3600",
  )
  inspect(r(Some(":/tmp/london")), content="File(\"/tmp/london\") GMT0/BST3600")
  // an invalid zone file falls through to the POSIX parser
  inspect(r(Some("EST5EDT")), content="Posix EST-18000/EDT-14400")
  inspect(r(Some(":JST-9")), content="Posix JST32400/JST32400")
  // unresolvable: UTC
  inspect(r(Some("Mars/Olympus")), content="Fallback UTC0/UTC0")
  inspect(r(Some(":")), content="Fallback UTC0/UTC0")
  inspect(r(Some("/tmp/missing")), content="Fallback UTC0/UTC0")
  // TZDIR is searched first
  inspect(
    describe(
      @tzdata.resolve(Some("Europe/London"), read_file=fs, tzdir="/opt/zones/"),
    ),
    content="File(\"/opt/zones/Europe/London\") AEDT39600/AEST36000",
  )
  // no /etc/localtime: UTC
  inspect(
    describe(@tzdata.resolve(None, read_file=fake_fs(Map([])))),
    content="Fallback UTC0/UTC0",
  )
}

///|
test "zone_file_candidates" {
  debug_inspect(
    @tzdata.zone_file_candidates("Europe/London", tzdir="/usr/share/zoneinfo"),
    content=(
      #|[
      #|  "/usr/share/zoneinfo/Europe/London",
      #|  "/usr/lib/zoneinfo/Europe/London",
      #|  "/usr/share/lib/zoneinfo/Europe/London",
      #|  "/etc/zoneinfo/Europe/London",
      #|]
    ),
  )
  debug_inspect(
    @tzdata.zone_file_candidates("/abs/zone", tzdir="/x"),
    content=(
      #|["/abs/zone"]
    ),
  )
}
