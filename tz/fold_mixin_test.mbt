// Upstream `TzFoldMixin`: ambiguous/imaginary time tests run against every
// zone provider (tzfile, tzrange, tzstr, tzlocal). `gettz(name)` returns
// the provider's zone for an IANA name; `restore` undoes any side effect
// (TZ changes for tzlocal).

///|
fn fold_mixin(
  gettz : (String) -> @datetime.Tz raise,
  restore? : () -> Unit = () => (),
) -> Unit raise {
  defer restore()
  let utc = @tz.utc
  // testFoldPositiveUTCOffset
  {
    let syd = gettz("Australia/Sydney")
    let t0_u = dt(2012, 3, 31, hour=15, minute=30, tz=utc) // AEST
    let t1_u = dt(2012, 3, 31, hour=16, minute=30, tz=utc) // AEDT
    let t0_syd0 = t0_u.astimezone(tz=syd)
    let t1_syd1 = t1_u.astimezone(tz=syd)
    assert_eq(t0_syd0.with_tzinfo(None), dt(2012, 4, 1, hour=2, minute=30))
    assert_eq(t1_syd1.with_tzinfo(None), dt(2012, 4, 1, hour=2, minute=30))
    assert_eq(t0_syd0.utcoffset(), Some(hours(11)))
    assert_eq(t1_syd1.utcoffset(), Some(hours(10)))
  }
  // testGapPositiveUTCOffset
  {
    let syd = gettz("Australia/Sydney")
    let t0_u = dt(2012, 10, 6, hour=15, minute=30, tz=utc) // AEST
    let t1_u = dt(2012, 10, 6, hour=16, minute=30, tz=utc) // AEDT
    let t0 = t0_u.astimezone(tz=syd)
    let t1 = t1_u.astimezone(tz=syd)
    assert_eq(t0.with_tzinfo(None), dt(2012, 10, 7, hour=1, minute=30))
    assert_eq(t1.with_tzinfo(None), dt(2012, 10, 7, hour=3, minute=30))
    assert_eq(t0.utcoffset(), Some(hours(10)))
    assert_eq(t1.utcoffset(), Some(hours(11)))
  }
  // testFoldNegativeUTCOffset
  {
    let tor = gettz("America/Toronto")
    let t0_u = dt(2011, 11, 6, hour=5, minute=30, tz=utc)
    let t1_u = dt(2011, 11, 6, hour=6, minute=30, tz=utc)
    let t0_tor = t0_u.astimezone(tz=tor)
    let t1_tor = t1_u.astimezone(tz=tor)
    assert_eq(t0_tor.with_tzinfo(None), dt(2011, 11, 6, hour=1, minute=30))
    assert_eq(t1_tor.with_tzinfo(None), dt(2011, 11, 6, hour=1, minute=30))
    assert_true(t0_tor.tzname() != t1_tor.tzname())
    assert_eq(t0_tor.utcoffset(), Some(hours(-4)))
    assert_eq(t1_tor.utcoffset(), Some(hours(-5)))
  }
  // testGapNegativeUTCOffset
  {
    let tor = gettz("America/Toronto")
    let t0_u = dt(2011, 3, 13, hour=6, minute=30, tz=utc)
    let t1_u = dt(2011, 3, 13, hour=7, minute=30, tz=utc)
    let t0 = t0_u.astimezone(tz=tor)
    let t1 = t1_u.astimezone(tz=tor)
    assert_eq(t0.with_tzinfo(None), dt(2011, 3, 13, hour=1, minute=30))
    assert_eq(t1.with_tzinfo(None), dt(2011, 3, 13, hour=3, minute=30))
    assert_true(t0 != t1)
    assert_eq(t0.utcoffset(), Some(hours(-5)))
    assert_eq(t1.utcoffset(), Some(hours(-4)))
  }
  // testFoldLondon
  {
    let lon = gettz("Europe/London")
    let t0_u = dt(2013, 10, 27, hour=0, minute=30, tz=utc) // BST
    let t1_u = dt(2013, 10, 27, hour=1, minute=30, tz=utc) // GMT
    let t0 = t0_u.astimezone(tz=lon)
    let t1 = t1_u.astimezone(tz=lon)
    assert_eq(t0.with_tzinfo(None), dt(2013, 10, 27, hour=1, minute=30))
    assert_eq(t1.with_tzinfo(None), dt(2013, 10, 27, hour=1, minute=30))
    assert_eq(t0.utcoffset(), Some(hours(1)))
    assert_eq(t1.utcoffset(), Some(hours(0)))
  }
  // testFoldIndependence
  {
    let nyc = gettz("America/New_York")
    let hour = hours(1)
    // Firmly 2015-11-01 0:30 EDT-4
    let pre_dst = dt(2015, 11, 1, hour=0, minute=30, tz=nyc)
    // Ambiguous between 2015-11-01 1:30 EDT-4 and 2015-11-01 1:30 EST-5
    let in_dst = pre_dst.add(hour)
    let in_dst_tzname_0 = in_dst.tzname() // Stash the tzname - EDT
    // Doing the arithmetic in UTC creates a date that is unambiguously
    // 2015-11-01 1:30 EDT-5
    let in_dst_via_utc = pre_dst
      .astimezone(tz=utc)
      .add(hour + hour)
      .astimezone(tz=nyc)
    // Make sure the dates are actually ambiguous
    assert_eq(in_dst, in_dst_via_utc)
    // Make sure we got the right folding behavior
    assert_true(in_dst_via_utc.tzname() != in_dst_tzname_0)
    // Now check to make sure in_dst's tzname hasn't changed
    assert_eq(in_dst_tzname_0, in_dst.tzname())
  }
  // testInZoneFoldEquality
  {
    let nyc = gettz("America/New_York")
    let dt0 = dt(2011, 11, 6, hour=1, minute=30, tz=nyc)
    let dt1 = @tz.enfold(dt0, fold=1)
    // Make sure these actually represent different times
    assert_true(dt0.astimezone(tz=utc) != dt1.astimezone(tz=utc))
    // Test that they compare equal
    assert_eq(dt0, dt1)
  }
  // _test_ambiguous_time
  let ambiguous = [
    // testAmbiguousNegativeUTCOffset
    (dt(2015, 11, 1, hour=1, minute=30), "America/New_York", true),
    // testAmbiguousPositiveUTCOffset
    (dt(2012, 4, 1, hour=2, minute=30), "Australia/Sydney", true),
    // testUnambiguousNegativeUTCOffset
    (dt(2015, 11, 1, hour=2, minute=30), "America/New_York", false),
    // testUnambiguousPositiveUTCOffset
    (dt(2012, 4, 1, hour=3, minute=30), "Australia/Sydney", false),
    // testUnambiguousGapNegativeUTCOffset
    (dt(2011, 3, 13, hour=2, minute=30), "America/New_York", false),
    // testUnambiguousGapPositiveUTCOffset
    (dt(2012, 10, 7, hour=2, minute=30), "Australia/Sydney", false),
  ]
  for case in ambiguous {
    let (d, tzid, expected) = case
    let tzi = gettz(tzid)
    assert_eq(@tz.datetime_ambiguous(d, tz=tzi), expected)
  }
  // _test_imaginary_time
  let imaginary = [
    // testImaginaryNegativeUTCOffset
    (dt(2011, 3, 13, hour=2, minute=30), "America/New_York", false),
    // testNotImaginaryNegativeUTCOffset
    (dt(2011, 3, 13, hour=1, minute=30), "America/New_York", true),
    // testImaginaryPositiveUTCOffset
    (dt(2012, 10, 7, hour=2, minute=30), "Australia/Sydney", false),
    // testNotImaginaryPositiveUTCOffset
    (dt(2012, 10, 7, hour=1, minute=30), "Australia/Sydney", true),
    // testNotImaginaryFoldNegativeUTCOffset
    (dt(2015, 11, 1, hour=1, minute=30), "America/New_York", true),
    // testNotImaginaryFoldPositiveUTCOffset
    (dt(2012, 4, 1, hour=3, minute=30), "Australia/Sydney", true),
  ]
  for case in imaginary {
    let (d, tzid, exists) = case
    let tzi = gettz(tzid)
    assert_eq(@tz.datetime_exists(d, tz=tzi), exists)
  }
  // testEqualAmbiguousComparison is skipped upstream ("Known failure").
}

///|
test "TZTest (tzfile): TzFoldMixin" {
  fold_mixin(name => zone(name))
}

///|
let tzrange_est : @datetime.Tz = @tz.tzrange(
  Some("EST"),
  stdoffset=hours(-5),
  dstabbr="EDT",
  dstoffset=hours(-4),
  start=rd(month=3, day=1, hour=2, weekday=@datetime.su.nth(Some(2))),
  end=rd(month=11, day=1, hour=1, weekday=@datetime.su.nth(Some(1))),
)

///|
let tzrange_aest : @datetime.Tz = @tz.tzrange(
  Some("AEST"),
  stdoffset=hours(10),
  dstabbr="AEDT",
  dstoffset=hours(11),
  start=rd(month=10, day=1, hour=2, weekday=@datetime.su.nth(Some(1))),
  end=rd(month=4, day=1, hour=2, weekday=@datetime.su.nth(Some(1))),
)

///|
let tzrange_lon : @datetime.Tz = @tz.tzrange(
  Some("GMT"),
  stdoffset=hours(0),
  dstabbr="BST",
  dstoffset=hours(1),
  start=rd(month=3, day=31, weekday=@datetime.su.nth(Some(-1)), hours=2),
  end=rd(month=10, day=31, weekday=@datetime.su.nth(Some(-1)), hours=1),
)

///|
test "TZRangeTest: TzFoldMixin" {
  fold_mixin(name => {
    match name {
      "Australia/Sydney" => tzrange_aest
      "America/Toronto" | "America/New_York" => tzrange_est
      "Europe/London" => tzrange_lon
      _ => fail("unexpected zone \{name}")
    }
  })
}

///|
test "TZStrTest: TzFoldMixin" {
  fold_mixin(name => {
    let s = match name {
      "Australia/Sydney" => "AEST-10AEDT,M10.1.0/2,M4.1.0/3"
      "America/Toronto" | "America/New_York" => "EST+5EDT,M3.2.0/2,M11.1.0/2"
      "Europe/London" => "GMT0BST,M3.5.0,M10.5.0"
      _ => fail("unexpected zone \{name}")
    }
    @tz.tzstr(s)
  })
}
