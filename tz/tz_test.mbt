// Port of upstream tests/test_tz.py (everything that does not need the
// system zoneinfo database, TZ changes, Windows, pickling or tzical).
// Zones that upstream gets from gettz() come from embedded TZif data here.

///|
test "TzUTCTest" {
  // testSingleton
  assert_true(@tz.tzutc().is_same(@tz.tzutc()))
  assert_true(@tz.tzutc().is_same(@tz.utc))
  let ct = dt(2009, 4, 1, hour=12, minute=11, second=13, tz=@tz.tzutc())
  // testOffset / testDst / testTzName
  assert_eq(ct.utcoffset(), Some(seconds(0)))
  assert_eq(ct.dst(), Some(seconds(0)))
  assert_eq(ct.tzname(), Some("UTC"))
  // testEquality / testInequality
  assert_eq(@tz.tzutc(), @tz.tzutc())
  assert_true(@tz.tzutc() != @tz.tzoffset(Some("UTC+4"), 14400))
  // testRepr
  inspect(@tz.tzutc(), content="tzutc()")
  // testTimeOnlyUTC
  let t = @datetime.Time::new(hour=13, minute=20, tzinfo=@tz.tzutc())
  assert_eq(t.utcoffset(), Some(hours(0)))
  // testAmbiguity
  let d = dt(2011, 9, 1, hour=2, minute=30, tz=@tz.tzutc())
  assert_false(@tz.datetime_ambiguous(d))
}

///|
test "TzOffsetTest" {
  // testTimedeltaOffset
  let est = @tz.tzoffset_delta(Some("EST"), hours(-5))
  let est_s = @tz.tzoffset(Some("EST"), -18000)
  assert_eq(est, est_s)
  // testTzNameNone
  let gmt5 = @tz.tzoffset(None, -18000)
  assert_eq(dt(2003, 10, 26, tz=gmt5).tzname(), None)
  // testTimeOnlyOffset
  let t = @datetime.Time::new(
    hour=13,
    minute=20,
    tzinfo=@tz.tzoffset(Some("+3"), 3600),
  )
  assert_eq(t.utcoffset(), Some(seconds(3600)))
  // testTzOffsetRepr
  inspect(
    @tz.tzoffset(Some("EST"), -5 * 3600),
    content="tzoffset('EST', -18000)",
  )
  // testEquality
  assert_eq(@tz.tzoffset(Some("UTC"), 0), @tz.tzoffset(Some("GMT"), 0))
  // testUTCEquality
  assert_eq(@tz.utc, @tz.tzoffset(Some("UTC"), 0))
  assert_eq(@tz.tzoffset(Some("UTC"), 0), @tz.utc)
  // testAmbiguity
  let d = dt(
    2011,
    9,
    1,
    hour=2,
    minute=30,
    tz=@tz.tzoffset(Some("EST"), -5 * 3600),
  )
  assert_false(@tz.datetime_ambiguous(d))
  // testTzOffsetInstance
  let tz1 = @tz.tzoffset_instance(Some("EST"), hours(-5))
  let tz2 = @tz.tzoffset_instance(Some("EST"), hours(-5))
  assert_false(tz1.is_same(tz2))
  assert_eq(tz1, tz2)
  // testTzOffsetSingletonDifferent
  assert_true(
    @tz.tzoffset_delta(Some("EST"), hours(-5)).is_same(
      @tz.tzoffset(Some("EST"), -18000),
    ),
  )
}

///|
test "test_tzoffset_singleton / test_tzoffset_is / test_tzoffset_is_not" {
  let tz_ref = @tz.tzoffset(Some("EST"), -18000)
  assert_true(@tz.tzoffset(Some("EST"), -18000).is_same(tz_ref))
  assert_true(@tz.tzoffset_delta(Some("EST"), hours(-5)).is_same(tz_ref))
  assert_true(
    @tz.tzoffset(Some("UTC"), 0).is_same(@tz.tzoffset(Some("UTC"), 0)),
  )
  assert_true(
    @tz.tzoffset_delta(None, hours(3)).is_same(
      @tz.tzoffset_delta(None, hours(3)),
    ),
  )
  assert_false(
    @tz.tzoffset(Some("EDT"), -14400).is_same(@tz.tzoffset(Some("EST"), -18000)),
  )
}

///|
test "test_tzoffset_sub_minute" {
  let delta = @datetime.TimeDelta::new(hours=12, seconds=30)
  let d = dt(2000, 1, 1, tz=@tz.tzoffset_delta(None, delta))
  assert_eq(d.utcoffset(), Some(delta))
}

///|
test "TzLocalTest" {
  // testEquality
  let tz1 = @tz.tzlocal()
  let tz2 = @tz.tzlocal()
  assert_true(tz1 == tz2)
  assert_false(tz1 != tz2)
  // testInequalityInvalid
  let lint = zone("Pacific/Kiritimati")
  assert_true(tz1 != lint)
  assert_false(tz1 == lint)
  // testRepr
  inspect(tz1, content="tzlocal()")
}

///|
test "TZRangeTest.testRangeCmp1 / testRangeCmp2" {
  assert_eq(
    @tz.tzstr("EST5EDT"),
    @tz.tzrange(
      Some("EST"),
      stdoffset=seconds(-18000),
      dstabbr="EDT",
      dstoffset=seconds(-14400),
      start=rd(hours=2, month=4, day=1, weekday=@datetime.su.nth(Some(1))),
      end=rd(hours=1, month=10, day=31, weekday=@datetime.su.nth(Some(-1))),
    ),
  )
  assert_eq(
    @tz.tzstr("EST5EDT"),
    @tz.tzrange(Some("EST"), stdoffset=seconds(-18000), dstabbr="EDT"),
  )
}

///|
test "TZRangeTest.testRangeOffsets" {
  let tzr = @tz.tzrange(
    Some("EST"),
    stdoffset=seconds(-18000),
    dstabbr="EDT",
    dstoffset=seconds(-14400),
    start=rd(hours=2, month=4, day=1, weekday=@datetime.su.nth(Some(2))),
    end=rd(hours=1, month=10, day=31, weekday=@datetime.su.nth(Some(-1))),
  )
  let dt_std = dt(2014, 4, 11, hour=12, tz=tzr) // STD
  let dt_dst = dt(2016, 4, 11, hour=12, tz=tzr) // DST
  assert_eq(dt_std.dst(), Some(hours(0)))
  assert_eq(dt_dst.dst(), Some(hours(1)))
  assert_eq(dt_std.utcoffset(), Some(hours(-5)))
  assert_eq(dt_dst.utcoffset(), Some(hours(-4)))
  assert_eq(dt_std.tzname(), Some("EST"))
  assert_eq(dt_dst.tzname(), Some("EDT"))
}

///|
test "TZRangeTest.testTimeOnlyRangeFixed / testTimeOnlyRange" {
  // This is a fixed-offset zone, so tzrange allows this
  let tz_range = @tz.tzrange(Some("dflt"), stdoffset=hours(-3))
  let t = @datetime.Time::new(hour=13, minute=20, tzinfo=tz_range)
  assert_eq(t.utcoffset(), Some(hours(-3)))
  // tzrange returns None because this zone has DST
  let tz_range = @tz.tzrange(
    Some("EST"),
    stdoffset=hours(-5),
    dstabbr="EDT",
    dstoffset=hours(-4),
  )
  let t = @datetime.Time::new(hour=13, minute=20, tzinfo=tz_range)
  assert_eq(t.utcoffset(), None)
}

///|
test "TZRangeTest.testBrokenIsDstHandling / TZTest.testGMTOffset" {
  // tzrange._isdst() was using a date() rather than a datetime().
  let d = dt(2007, 8, 6, hour=4, minute=10, tz=@tz.utc)
  assert_eq(
    d.astimezone(tz=@tz.gettz(name="GMT+2").unwrap()),
    dt(2007, 8, 6, hour=6, minute=10, tz=@tz.tzstr("GMT+2")),
  )
  assert_eq(
    d.astimezone(tz=@tz.tzstr("GMT+2")),
    dt(2007, 8, 6, hour=6, minute=10, tz=@tz.tzstr("GMT+2")),
  )
  assert_eq(
    d.astimezone(tz=@tz.gettz(name="UTC-2").unwrap()),
    dt(2007, 8, 6, hour=2, minute=10, tz=@tz.tzstr("UTC-2")),
  )
}

///|
test "TZRangeTest.testRangeTimeDelta" {
  let est5edt_td = @tz.tzrange(
    Some("EST"),
    stdoffset=hours(-5),
    dstabbr="EDT",
    dstoffset=hours(-4),
  )
  let est5edt_sec = @tz.tzrange(
    Some("EST"),
    stdoffset=seconds(-18000),
    dstabbr="EDT",
    dstoffset=seconds(-14400),
  )
  assert_eq(est5edt_td, est5edt_sec)
}

///|
test "TZRangeTest.testRangeEquality" {
  let range = (std : String, stdoff : Int, dst : String, dstoff : Int) => {
    @tz.tzrange(
      Some(std),
      stdoffset=seconds(stdoff),
      dstabbr=dst,
      dstoffset=seconds(dstoff),
    )
  }
  let tzr1 = range("EST", -18000, "EDT", -14400)
  // Standard abbreviation different
  assert_true(tzr1 != range("ET", -18000, "EDT", -14400))
  // DST abbreviation different
  assert_true(tzr1 != range("EST", -18000, "EMT", -14400))
  // STD offset different
  assert_true(tzr1 != range("EST", -14000, "EDT", -14400))
  // DST offset different
  assert_true(tzr1 != range("EST", -18000, "EDT", -18000))
  // Start delta different
  let tzr6 = @tz.tzrange(
    Some("EST"),
    stdoffset=seconds(-18000),
    dstabbr="EDT",
    dstoffset=seconds(-14400),
    start=rd(hours=1, month=3, day=1, weekday=@datetime.su.nth(Some(2))),
  )
  assert_true(tzr1 != tzr6)
  // End delta different
  let tzr7 = @tz.tzrange(
    Some("EST"),
    stdoffset=seconds(-18000),
    dstabbr="EDT",
    dstoffset=seconds(-14400),
    end=rd(hours=1, month=11, day=1, weekday=@datetime.su.nth(Some(2))),
  )
  assert_true(tzr1 != tzr7)
  // A tzrange is not equal to other kinds of zones
  assert_true(tzr1 != @tz.utc)
  assert_true(@tz.tzrange(None) != @tz.utc)
  inspect(tzr1, content="tzrange(...)")
}

///|
test "TZStrTest.testStrStr" {
  assert_eq(
    dt(2003, 4, 6, hour=1, minute=59, tz=@tz.tzstr("EST5EDT")).tzname(),
    Some("EST"),
  )
  assert_eq(
    dt(2003, 4, 6, hour=2, minute=0, tz=@tz.tzstr("EST5EDT")).tzname(),
    Some("EDT"),
  )
}

///|
test "TZStrTest.testStrInequality / testStrInequalityStartEnd" {
  let tzs1 = @tz.tzstr("EST5EDT4")
  // Standard abbreviation different
  assert_true(tzs1 != @tz.tzstr("ET5EDT4"))
  // DST abbreviation different
  assert_true(tzs1 != @tz.tzstr("EST5EMT"))
  // STD offset different
  assert_true(tzs1 != @tz.tzstr("EST4EDT4"))
  // DST offset different
  assert_true(tzs1 != @tz.tzstr("EST5EDT3"))
  // Start delta different
  assert_true(tzs1 != @tz.tzstr("EST5EDT4,M4.2.0/02:00:00,M10-5-0/02:00"))
  // End delta different
  assert_true(tzs1 != @tz.tzstr("EST5EDT4,M4.2.0/02:00:00,M11-5-0/02:00"))
}

///|
test "TZStrTest.testPosixOffset" {
  let tz1 = @tz.tzstr("UTC-3")
  assert_eq(dt(2015, 1, 1, tz=tz1).utcoffset(), Some(hours(-3)))
  let tz2 = @tz.tzstr("UTC-3", posix_offset=true)
  assert_eq(dt(2015, 1, 1, tz=tz2).utcoffset(), Some(hours(3)))
}

///|
test "TZStrTest.testTzStrRepr" {
  inspect(@tz.tzstr("EST5EDT4"), content="tzstr('EST5EDT4')")
  inspect(@tz.tzstr("EST"), content="tzstr('EST')")
}

///|
test "TZStrTest.testTzStrFailure" {
  try @tz.tzstr("InvalidString;439999") catch {
    e => inspect(e, content="ValueError: unknown string format")
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "TZStrTest.testTzStrSingleton / testTzStrSingletonPosix / testTzStrInstance" {
  let tz1 = @tz.tzstr("EST5EDT")
  let tz2 = @tz.tzstr("CST4CST")
  let tz3 = @tz.tzstr("EST5EDT")
  assert_false(tz1.is_same(tz2))
  assert_true(tz1.is_same(tz3))
  let tz_t1 = @tz.tzstr("GMT+3", posix_offset=true)
  let tz_f1 = @tz.tzstr("GMT+3", posix_offset=false)
  let tz_t2 = @tz.tzstr("GMT+3", posix_offset=true)
  let tz_f2 = @tz.tzstr("GMT+3")
  assert_true(tz_t1.is_same(tz_t2))
  assert_false(tz_t1.is_same(tz_f1))
  assert_true(tz_f1.is_same(tz_f2))
  let tz1 = @tz.tzstr("EST5EDT")
  let tz2 = @tz.tzstr_instance("EST5EDT")
  let tz3 = @tz.tzstr_instance("EST5EDT")
  assert_false(tz1.is_same(tz2))
  assert_false(tz2.is_same(tz3))
  // Ensure that these still are all the same zone
  assert_true(tz1 == tz2 && tz2 == tz3)
}

///|
test "test_valid_GNU_tzstr" {
  let su = @datetime.su
  let th = @datetime.th
  let cases : Array[(String, @datetime.Tz)] = [
    ("", @tz.tzrange(None)),
    (
      "EST+5EDT,M3.2.0/2,M11.1.0/12",
      @tz.tzrange(
        Some("EST"),
        stdoffset=seconds(-18000),
        dstabbr="EDT",
        dstoffset=seconds(-14400),
        start=rd(month=3, day=1, weekday=su.nth(Some(2)), hours=2),
        end=rd(month=11, day=1, weekday=su.nth(Some(1)), hours=11),
      ),
    ),
    (
      // This is DST all year, Western Argentina Summer Time
      "WART4WARST,J1/0,J365/25",
      @tz.tzrange(
        Some("WART"),
        stdoffset=hours(-4),
        dstabbr="WARST",
        start=rd(month=1, day=1, hours=0),
        end=rd(month=12, day=31, days=1),
      ),
    ),
    (
      // Israel Standard / Daylight Time
      "IST-2IDT,M3.4.4/26,M10.5.0",
      @tz.tzrange(
        Some("IST"),
        stdoffset=hours(2),
        dstabbr="IDT",
        start=rd(month=3, day=1, weekday=th.nth(Some(4)), days=1, hours=2),
        end=rd(month=10, day=31, weekday=su.nth(Some(-1)), hours=1),
      ),
    ),
    (
      "WGT3WGST,M3.5.0/2,M10.5.0/1",
      @tz.tzrange(
        Some("WGT"),
        stdoffset=hours(-3),
        dstabbr="WGST",
        start=rd(month=3, day=31, weekday=su.nth(Some(-1)), hours=2),
        end=rd(month=10, day=31, weekday=su.nth(Some(-1)), hours=0),
      ),
    ),
    // Different offset specifications
    (
      "WGT0300WGST",
      @tz.tzrange(Some("WGT"), stdoffset=hours(-3), dstabbr="WGST"),
    ),
    (
      "WGT03:00WGST",
      @tz.tzrange(Some("WGT"), stdoffset=hours(-3), dstabbr="WGST"),
    ),
    (
      "AEST-1100AEDT",
      @tz.tzrange(Some("AEST"), stdoffset=hours(11), dstabbr="AEDT"),
    ),
    (
      "AEST-11:00AEDT",
      @tz.tzrange(Some("AEST"), stdoffset=hours(11), dstabbr="AEDT"),
    ),
  ]
  // Different time formats
  for
    s in [
      "EST5EDT,M3.2.0/4:00,M11.1.0/3:00", "EST5EDT,M3.2.0/04:00,M11.1.0/03:00", "EST5EDT,M3.2.0/0400,M11.1.0/0300",
    ] {
    cases.push(
      (
        s,
        @tz.tzrange(
          Some("EST"),
          stdoffset=hours(-5),
          dstabbr="EDT",
          start=rd(month=3, day=1, weekday=su.nth(Some(2)), hours=4),
          end=rd(month=11, day=1, weekday=su.nth(Some(1)), hours=2),
        ),
      ),
    )
  }
  for case in cases {
    let (s, expected) = case
    let tzi = @tz.tzstr(s)
    if tzi != expected {
      fail("tzstr(\{s}) != expected")
    }
  }
}

///|
test "test_valid_dateutil_format" {
  let su = @datetime.su
  let range = (
    dstoffset : @datetime.TimeDelta?,
    start : @relativedelta.RelativeDelta,
    end : @relativedelta.RelativeDelta,
  ) => {
    @tz.tzrange(
      Some("EST"),
      stdoffset=hours(-5),
      dstabbr="EDT",
      dstoffset?,
      start~,
      end~,
    )
  }
  let s4 = rd(month=5, day=1, weekday=su.nth(Some(4)), hours=2)
  let cases : Array[(String, @datetime.Tz)] = [
    (
      "EST5EDT,5,4,0,7200,11,3,0,7200",
      range(None, s4, rd(month=11, day=1, weekday=su.nth(Some(3)), hours=1)),
    ),
    (
      "EST5EDT,5,-4,0,7200,11,3,0,7200",
      range(
        None,
        rd(hours=2, month=5, day=31, weekday=su.nth(Some(-4))),
        rd(hours=1, month=11, day=1, weekday=su.nth(Some(3))),
      ),
    ),
    (
      "EST5EDT,5,4,0,7200,11,-3,0,7200",
      range(None, s4, rd(hours=1, month=11, day=31, weekday=su.nth(Some(-3)))),
    ),
    (
      "EST5EDT,5,4,0,7200,11,-3,0,7200,3600",
      range(None, s4, rd(hours=1, month=11, day=31, weekday=su.nth(Some(-3)))),
    ),
    (
      "EST5EDT,5,4,0,7200,11,-3,0,7200,-3600",
      range(
        Some(hours(-6)),
        s4,
        rd(hours=3, month=11, day=31, weekday=su.nth(Some(-3))),
      ),
    ),
    (
      "EST5EDT,5,4,0,7200,11,-3,0,7200,+7200",
      range(
        Some(hours(-3)),
        s4,
        rd(hours=0, month=11, day=31, weekday=su.nth(Some(-3))),
      ),
    ),
    (
      "EST5EDT,5,4,0,7200,11,-3,0,7200,+3600",
      range(None, s4, rd(hours=1, month=11, day=31, weekday=su.nth(Some(-3)))),
    ),
  ]
  for case in cases {
    let (s, expected) = case
    let tzi = @tz.tzstr_instance(s)
    if tzi != expected {
      fail("tzstr(\{s}) != expected")
    }
  }
}

///|
test "test_invalid_GNU_tzstr" {
  for
    s in [
      "hdfiughdfuig,dfughdfuigpu87ñ::", ",dfughdfuigpu87ñ::", "-1:WART4WARST,J1,J365/25",
      "WART4WARST,J1,J365/-25", "IST-2IDT,M3.4.-1/26,M10.5.0", "IST-2IDT,M3,2000,1/26,M10,5,0",
    ] {
    try @tz.tzstr(s) catch {
      @datetime.ValueError(_) => ()
      e => fail("tzstr(\{s}): unexpected error \{e}")
    } noraise {
      _ => fail("tzstr(\{s}) should fail")
    }
  }
}

///|
/// Different representations of the same default rule set.
let default_tzstr_rules_equiv_2003 : Array[String] = [
  "EST5EDT", "EST5EDT4,M4.1.0/02:00:00,M10-5-0/02:00", "EST5EDT4,95/02:00:00,298/02:00",
  "EST5EDT4,J96/02:00:00,J299/02:00", "EST5EDT4,J96/02:00:00,J299/02",
]

///|
test "test_tzstr_default_start / test_tzstr_default_end" {
  for s in default_tzstr_rules_equiv_2003 {
    let tzi = @tz.tzstr(s)
    let dt_std = dt(2003, 4, 6, hour=1, minute=59, tz=tzi)
    let dt_dst = dt(2003, 4, 6, hour=2, minute=0, tz=tzi)
    assert_eq(tz_tuple(dt_std), est_tuple)
    assert_eq(tz_tuple(dt_dst), edt_tuple)
    let dt_dst = dt(2003, 10, 26, hour=0, minute=59, tz=tzi)
    let dt_dst_ambig = dt(2003, 10, 26, hour=1, minute=0, tz=tzi)
    let dt_std_ambig = @tz.enfold(dt_dst_ambig, fold=1)
    let dt_std = dt(2003, 10, 26, hour=2, minute=0, tz=tzi)
    assert_eq(tz_tuple(dt_dst), edt_tuple)
    assert_eq(tz_tuple(dt_dst_ambig), edt_tuple)
    assert_eq(tz_tuple(dt_std_ambig), est_tuple)
    assert_eq(tz_tuple(dt_std), est_tuple)
  }
}

///|
test "test_tzstr_default_cmp" {
  for s1 in ["EST5EDT", "EST5EDT4,M4.1.0/02:00:00,M10-5-0/02:00"] {
    for s2 in ["EST5EDT", "EST5EDT4,M4.1.0/02:00:00,M10-5-0/02:00"] {
      assert_eq(@tz.tzstr(s1), @tz.tzstr(s2))
    }
  }
}

///|
fn est5edt_file() -> @datetime.Tz {
  @tz.tzfile_from_bytes(zone_bytes("upstream:TZFILE_EST5EDT")) catch {
    e => abort(e.to_string())
  }
}

///|
test "TZTest.testFileStart1 / testFileEnd1 / testFileLastTransition" {
  let tzc = est5edt_file()
  assert_eq(dt(2003, 4, 6, hour=1, minute=59, tz=tzc).tzname(), Some("EST"))
  assert_eq(dt(2003, 4, 6, hour=2, minute=0, tz=tzc).tzname(), Some("EDT"))
  assert_eq(dt(2003, 10, 26, hour=0, minute=59, tz=tzc).tzname(), Some("EDT"))
  let end_est = @tz.enfold(dt(2003, 10, 26, hour=1, minute=0, tz=tzc))
  assert_eq(end_est.tzname(), Some("EST"))
  // After the last transition, it goes to standard time in perpetuity
  assert_eq(dt(2037, 10, 25, hour=0, minute=59, tz=tzc).tzname(), Some("EDT"))
  let last_date = @tz.enfold(dt(2037, 10, 25, hour=1, minute=0, tz=tzc), fold=1)
  assert_eq(last_date.tzname(), Some("EST"))
  assert_eq(dt(2038, 5, 25, hour=12, tz=tzc).tzname(), Some("EST"))
}

///|
test "TZTest.testInvalidFile" {
  try @tz.tzfile_from_bytes(b"BadFile") catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
  // truncated data
  let data = zone_bytes("upstream:NEW_YORK")
  try @tz.tzfile_from_bytes(data[0:100]) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "TZTest.testFilestreamWithNameRepr" {
  let tzc = @tz.tzfile_from_bytes(
    zone_bytes("upstream:TZFILE_EST5EDT"),
    filename="foo",
  )
  inspect(tzc, content="tzfile('foo')")
  inspect(zone("US/Eastern"), content="tzfile('US/Eastern')")
}

///|
test "TZTest.testGMTHasNoDaylight" {
  let d = dt(2007, 8, 6, hour=4, minute=10)
  assert_eq(@tz.gettz(name="GMT+2").unwrap().dst(Some(d)), Some(hours(0)))
}

///|
test "tzfile equality" {
  // Two tzfiles from the same data are equal but not identical
  let a = @tz.tzfile_from_bytes(zone_bytes("America/New_York"), filename="a")
  let b = @tz.tzfile_from_bytes(zone_bytes("America/New_York"), filename="b")
  assert_false(a.is_same(b))
  assert_eq(a, b)
  // US/Eastern is a link to America/New_York
  assert_eq(zone("US/Eastern"), zone("America/New_York"))
  assert_true(zone("America/Toronto") != zone("America/New_York"))
  assert_true(zone("UTC") != @tz.utc)
  assert_true(zone("EST5EDT") != @tz.tzstr("EST5EDT"))
}

///|
test "test_tzfile_sub_minute_offset" {
  let tzc = @tz.tzfile_from_bytes(zone_bytes("upstream:EUROPE_HELSINKI"))
  let offset = @datetime.TimeDelta::new(hours=1, minutes=39, seconds=52)
  assert_eq(dt(1900, 1, 1, tz=tzc).utcoffset(), Some(offset))
}

///|
test "test_samoa_transition" {
  // utcoffset() was erroneously returning +14:00 an hour early (GH #812)
  let apia = zone("Pacific/Apia")
  let d = dt(2011, 12, 29, hour=23, minute=59, tz=apia)
  assert_eq(d.utcoffset(), Some(hours(-10)))
  // Make sure the transition actually works, too
  let dt_after = d
    .astimezone(tz=@tz.utc)
    .add(@datetime.TimeDelta::new(minutes=1))
    .astimezone(tz=apia)
  assert_eq(dt_after, dt(2011, 12, 31, tz=apia))
  assert_eq(dt_after.utcoffset(), Some(hours(14)))
}

///|
test "GettzTest.testPortugalDST (embedded data)" {
  // In 1996, Portugal changed from CET to WET
  let portugal = zone("Portugal")
  let t_cet = dt(1996, 3, 31, hour=1, minute=59, tz=portugal)
  assert_eq(t_cet.tzname(), Some("CET"))
  assert_eq(t_cet.utcoffset(), Some(hours(1)))
  assert_eq(t_cet.dst(), Some(hours(0)))
  let t_west = dt(1996, 3, 31, hour=2, minute=1, tz=portugal)
  assert_eq(t_west.tzname(), Some("WEST"))
  assert_eq(t_west.utcoffset(), Some(hours(1)))
  assert_eq(t_west.dst(), Some(hours(1)))
}

///|
test "GettzTest.testTimeOnly* (embedded data)" {
  let t = @datetime.Time::new(hour=13, minute=20, tzinfo=zone("Europe/Minsk"))
  assert_eq(t.utcoffset(), None)
  assert_eq(t.dst(), None)
  assert_eq(t.tzname(), None)
  // testTimeOnlyFormatZ
  assert_eq(t.strftime("%H%M%Z"), "1320")
}

///|
/// A plain `tzinfo` without `is_ambiguous` support where dates between
/// `start` and `end` are ambiguous (upstream `_get_no_support_tzinfo`).
struct FoldingTzInfo {
  start : @datetime.DateTime
  end : @datetime.DateTime
  dst_only : Bool
}

///|
fn FoldingTzInfo::in_fold(
  self : FoldingTzInfo,
  d : @datetime.DateTime?,
) -> Bool {
  guard d is Some(d) else { return false }
  let n = d.with_tzinfo(None)
  self.start <= n && n < self.end && n.fold == 1
}

///|
impl @datetime.TzInfo for FoldingTzInfo with fn utcoffset(self, d) {
  if !self.dst_only && self.in_fold(d) {
    Some(hours(-1))
  } else {
    Some(hours(0))
  }
}

///|
impl @datetime.TzInfo for FoldingTzInfo with fn dst(self, d) {
  if self.in_fold(d) {
    Some(hours(1))
  } else {
    Some(hours(0))
  }
}

///|
impl @datetime.TzInfo for FoldingTzInfo with fn tzname(_, _) {
  None
}

///|
impl @datetime.TzInfo for FoldingTzInfo with fn repr(_) {
  "FoldingTzInfo()"
}

///|
fn no_support_tzinfo(dst_only? : Bool = false) -> @datetime.Tz {
  @datetime.Tz::new(FoldingTzInfo::{
    start: dt(2018, 9, 1, hour=1),
    end: dt(2018, 9, 1, hour=2),
    dst_only,
  })
}

///|
test "DatetimeAmbiguousTest" {
  // testNoTzSpecified
  try @tz.datetime_ambiguous(dt(2016, 4, 1, hour=2, minute=9)) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
  // testNoSupportAmbiguity* and testIncompatibleAmbiguity* (a zone whose
  // is_ambiguous fails is the same as one without it here)
  let tzi = no_support_tzinfo()
  assert_true(@tz.datetime_ambiguous(dt(2018, 9, 1, hour=1, minute=30), tz=tzi))
  assert_true(@tz.datetime_ambiguous(dt(2018, 9, 1, hour=1, minute=30, tz=tzi)))
  assert_false(
    @tz.datetime_ambiguous(dt(2018, 10, 1, hour=12, minute=30), tz=tzi),
  )
  assert_false(
    @tz.datetime_ambiguous(dt(2018, 10, 1, hour=12, minute=30, tz=tzi)),
  )
  let tzi = no_support_tzinfo(dst_only=true)
  assert_true(@tz.datetime_ambiguous(dt(2018, 9, 1, hour=1, minute=30), tz=tzi))
  assert_false(
    @tz.datetime_ambiguous(dt(2018, 10, 1, hour=12, minute=30), tz=tzi),
  )
  // testSupportAmbiguity*
  let tzi = zone("US/Eastern")
  assert_true(
    @tz.datetime_ambiguous(dt(2011, 11, 6, hour=1, minute=30), tz=tzi),
  )
  assert_true(
    @tz.datetime_ambiguous(dt(2011, 11, 6, hour=1, minute=30, tz=tzi)),
  )
  assert_false(
    @tz.datetime_ambiguous(dt(2011, 11, 6, hour=4, minute=30), tz=tzi),
  )
  assert_false(
    @tz.datetime_ambiguous(dt(2011, 11, 6, hour=4, minute=30, tz=tzi)),
  )
  // testSpecifiedTzOverridesAttached
  let d = dt(2011, 11, 6, hour=1, minute=30, tz=zone("Australia/Sydney"))
  assert_false(@tz.datetime_ambiguous(d))
  assert_true(@tz.datetime_ambiguous(d, tz=zone("US/Eastern")))
}

///|
test "DatetimeExistsTest" {
  try @tz.datetime_exists(dt(2016, 4, 1, hour=2, minute=9)) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
  let tzi = zone("Australia/Sydney")
  assert_false(@tz.datetime_exists(dt(2012, 10, 7, hour=2, minute=30), tz=tzi))
  assert_false(@tz.datetime_exists(dt(2012, 10, 7, hour=2, minute=30, tz=tzi)))
  assert_true(@tz.datetime_exists(dt(2012, 10, 7, hour=10, minute=30), tz=tzi))
  assert_true(@tz.datetime_exists(dt(2012, 10, 7, hour=10, minute=30, tz=tzi)))
  // testSpecifiedTzOverridesAttached
  let d = dt(2012, 10, 7, hour=2, minute=30, tz=zone("US/Eastern")) // exists
  assert_false(@tz.datetime_exists(d, tz=zone("Australia/Sydney")))
}

///|
test "TestEnfold" {
  // test_enter_fold_default / test_enter_fold
  assert_eq(@tz.enfold(dt(2020, 1, 19, hour=3, minute=32)).fold, 1)
  assert_eq(@tz.enfold(dt(2020, 1, 19, hour=3, minute=32), fold=1).fold, 1)
  // test_exit_fold / test_defold
  assert_eq(@tz.enfold(dt(2020, 1, 19, hour=3, minute=32), fold=0).fold, 0)
  let d = @tz.enfold(dt(2020, 1, 19, hour=3, minute=32), fold=1)
  assert_eq(@tz.enfold(d, fold=0).fold, 0)
  // test_fold_replace_args
  let d = @tz.enfold(
    @datetime.DateTime::new(
      1950,
      1,
      2,
      hour=12,
      minute=30,
      second=15,
      microsecond=8,
    ),
    fold=1,
  )
  let d2 = d.replace(
    year=1952,
    month=2,
    day=3,
    hour=13,
    minute=31,
    second=16,
    microsecond=9,
  )
  assert_eq(
    d2,
    @tz.enfold(
      @datetime.DateTime::new(
        1952,
        2,
        3,
        hour=13,
        minute=31,
        second=16,
        microsecond=9,
      ),
      fold=1,
    ),
  )
  assert_eq(d2.fold, 1)
}

///|
/// `dt` and `res` are "the same object": equal fields, fold and zone.
fn assert_same_dt(
  res : @datetime.DateTime,
  d : @datetime.DateTime,
) -> Unit raise {
  assert_eq(res.repr(), d.repr())
  assert_eq(res.fold, d.fold)
  assert_true(@datetime.same_tz(res.tzinfo, d.tzinfo))
}

///|
test "ImaginaryDateTest" {
  let cases = [
    (
      "Australia/Canberra",
      dt(2018, 10, 7, hour=2, minute=30),
      dt(2018, 10, 7, hour=3, minute=30),
    ),
    (
      "Europe/London",
      dt(2018, 3, 25, hour=1, minute=30),
      dt(2018, 3, 25, hour=2, minute=30),
    ),
    (
      "Europe/Kiev",
      dt(2018, 3, 25, hour=3, minute=30),
      dt(2018, 3, 25, hour=4, minute=30),
    ),
  ]
  for case in cases {
    let (name, d, expected) = case
    let tzi = zone(name)
    assert_eq(
      @tz.resolve_imaginary(d.with_tzinfo(Some(tzi))),
      expected.with_tzinfo(Some(tzi)),
    )
  }
}

///|
test "test_resolve_imaginary_ambiguous / test_resolve_imaginary_existing" {
  let ambiguous = [
    dt(2017, 11, 5, hour=1, minute=30, tz=zone("America/New_York")),
    dt(2018, 10, 28, hour=1, minute=30, tz=zone("Europe/London")),
    dt(2017, 4, 2, hour=2, minute=30, tz=zone("Australia/Sydney")),
  ]
  for d in ambiguous {
    assert_same_dt(@tz.resolve_imaginary(d), d)
    let d_f = @tz.enfold(d)
    assert_same_dt(@tz.resolve_imaginary(d_f), d_f)
  }
  let existing = [
    dt(2017, 6, 2, hour=12, minute=30, tz=zone("America/New_York")),
    dt(2018, 4, 2, hour=9, minute=30, tz=zone("Europe/London")),
    dt(2017, 2, 2, hour=16, minute=30, tz=zone("Australia/Sydney")),
    dt(2017, 12, 2, hour=12, minute=30, tz=zone("America/New_York")),
    dt(2018, 12, 2, hour=9, minute=30, tz=zone("Europe/London")),
    dt(2017, 6, 2, hour=16, minute=30, tz=zone("Australia/Sydney")),
    dt(2025, 9, 25, hour=1, minute=17, tz=@tz.utc),
    dt(2025, 9, 25, hour=1, minute=17, tz=@tz.tzoffset(Some("EST"), -18000)),
    dt(2019, 3, 4),
  ]
  for d in existing {
    assert_same_dt(@tz.resolve_imaginary(d), d)
  }
}

///|
test "test_resolve_imaginary" {
  let cases = [
    (
      "Europe/London",
      dt(2018, 3, 25, hour=1, minute=30),
      dt(2018, 3, 25, hour=2, minute=30),
    ),
    (
      "America/New_York",
      dt(2017, 3, 12, hour=2, minute=30),
      dt(2017, 3, 12, hour=3, minute=30),
    ),
    ("Australia/Sydney", dt(2014, 10, 5, hour=2), dt(2014, 10, 5, hour=3)),
    // The 2018d+ Kiritimati data
    (
      "Pacific/Kiritimati",
      dt(1994, 12, 31, hour=12, minute=30),
      dt(1995, 1, 1, hour=12, minute=30),
    ),
    (
      "Africa/Monrovia",
      dt(1972, 1, 7, minute=30),
      dt(1972, 1, 7, hour=1, minute=14, second=30),
    ),
  ]
  for case in cases {
    let (name, d, expected) = case
    let tzi = zone(name)
    let d = d.with_tzinfo(Some(tzi))
    let expected = expected.with_tzinfo(Some(tzi))
    let dt_r = @tz.resolve_imaginary(d)
    assert_eq(dt_r, expected)
    assert_eq(dt_r.tzname(), expected.tzname())
    assert_eq(dt_r.utcoffset(), expected.utcoffset())
  }
}

///|
test "gettz without the file system: TZ strings, UTC, bad names" {
  // test_gettz_badzone / test_gettz_badzone_unicode
  assert_true(@tz.gettz(name="Fake.Region/Abcdefghijklmnop") is None)
  assert_true(@tz.gettz(name="🐼") is None)
  // testGettz / testGetTzEquality
  let u = @tz.gettz(name="UTC").unwrap()
  ignore(u.to_string())
  assert_eq(@tz.gettz(name="UTC").unwrap(), @tz.gettz(name="UTC").unwrap())
  // TZ strings are parsed by tzstr and cached
  let a = @tz.gettz(name="EST5EDT4,M3.2.0/2,M11.1.0/2").unwrap()
  inspect(a, content="tzstr('EST5EDT4,M3.2.0/2,M11.1.0/2')")
  assert_true(@tz.gettz(name="EST5EDT4,M3.2.0/2,M11.1.0/2").unwrap().is_same(a))
  // an invalid TZ string with a digit gives None
  assert_true(@tz.gettz(name="Invalid;439999") is None)
  // After cache_clear the TZ string still resolves to the same object,
  // because tzstr() has its own factory cache (as in Python).
  @tz.gettz_cache_clear()
  assert_true(@tz.gettz(name="EST5EDT4,M3.2.0/2,M11.1.0/2").unwrap().is_same(a))
  let n1 = @tz.gettz_nocache(name="EST5EDT4,M3.2.0/2,M11.1.0/2").unwrap()
  assert_true(n1.is_same(a))
  // test_gettz_same_result_for_none_and_empty_string
  let local_from_none = @tz.gettz()
  let local_from_empty_string = @tz.gettz(name="")
  assert_true(local_from_none is Some(_))
  assert_true(local_from_empty_string is Some(_))
  assert_eq(local_from_none, local_from_empty_string)
}

///|
test "gettz_set_cache_size rejects negative sizes" {
  // Python: gettz.set_cache_size(-1) raises KeyError (popitem on an empty
  // OrderedDict); we raise ValueError before touching the cache.
  try @tz.gettz_set_cache_size(-1) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
  // the cache still works afterwards (this used to abort)
  let u = @tz.gettz(name="UTC").unwrap()
  assert_true(@tz.gettz(name="UTC").unwrap().is_same(u))
  let e = @tz.gettz(name="EST5EDT").unwrap()
  // size 0 is valid; cached zones stay identical (no weak references)
  @tz.gettz_set_cache_size(0)
  assert_true(@tz.gettz(name="EST5EDT").unwrap().is_same(e))
  assert_true(@tz.gettz(name="UTC").unwrap().is_same(u))
  @tz.gettz_set_cache_size(8)
}

///|
test "regressions from review" {
  // tzrange.fromutc propagates transition errors (Python OverflowError)
  let z = @tz.tzstr("X0Y,J365/99,J1")
  try dt(9999, 6, 1, tz=@tz.utc).astimezone(tz=z) catch {
    @datetime.OverflowError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected OverflowError")
  }
  // tzoffset repr truncates toward zero like int(total_seconds())
  inspect(
    @tz.tzoffset_delta(Some("X"), @datetime.TimeDelta::new(microseconds=-1)),
    content="tzoffset('X', 0)",
  )
  // offsets that do not fit in 32 bits make a TZ string invalid
  try @tz.tzstr("X1193046:28") catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
  // a leap second count larger than the data is a truncated file
  let buf = Buffer()
  buf.write_bytes(b"TZif")
  for _ in 0..<16 {
    buf.write_byte(0)
  }
  for count in [0, 1, 0x20000000, 0, 1, 0] {
    buf.write_int_be(count)
  }
  for _ in 0..<7 {
    buf.write_byte(0)
  }
  try @tz.tzfile_from_bytes(buf.to_bytes()) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}
