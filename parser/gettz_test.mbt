// Upstream tests that need tz.gettz (system zoneinfo; native and js only).
// They are skipped silently when the zone database is not installed.

///|
test "test_parser::test_parse_tzinfos_fold" {
  guard @tz.gettz(name="America/New_York") is Some(nyc) else { return }
  let tzinfos = @parser.Table({ "EST": Zone(nyc), "EDT": Zone(nyc) })
  let dt_exp = @tz.enfold(
    dt(2011, 11, 6, hour=1, minute=30).with_tzinfo(Some(nyc)),
    fold=1,
  )
  let d = @parser.parse("2011-11-06T01:30 EST", tzinfos~)
  assert_eq(d, dt_exp)
  assert_true(same_tz(d, dt_exp))
  assert_eq(d.fold, dt_exp.fold)
  assert_eq(d.astimezone(tz=@tz.utc), dt_exp.astimezone(tz=@tz.utc))
}

///|
test "test_isoparse_prop::test_timespec_auto (gettz zones)" {
  let zones = []
  for name in ["US/Eastern", "US/Pacific", "Australia/Sydney", "Europe/London"] {
    if @tz.gettz(name~) is Some(z) {
      zones.push(z)
    }
  }
  if zones.length() == 0 {
    return
  }
  fn check(dt : @datetime.DateTime, sep : Char) raise {
    // Assume offset has no sub-second components
    guard dt.utcoffset() is Some(off)
    if off.seconds % 60 != 0 || off.microseconds != 0 {
      return
    }
    let dt_rt = @parser.isoparse(dt.isoformat(sep~))
    // The round trip preserves the wall time and the offset.
    assert_eq(dt_rt.with_tzinfo(None), dt.with_tzinfo(None))
    assert_eq(dt_rt.utcoffset(), dt.utcoffset())
    // PEP 495: comparisons with ambiguous/imaginary datetimes are false.
    let ambiguous = @tz.enfold(dt, fold=0).utcoffset() !=
      @tz.enfold(dt, fold=1).utcoffset()
    if ambiguous {
      assert_true(dt_rt != dt)
    } else {
      assert_eq(dt_rt, dt)
    }
  }

  // Ambiguous in US/Eastern: the first 01:00 (EDT) and the second (EST)
  if @tz.gettz(name="US/Eastern") is Some(eastern) {
    let amb = dt(2020, 11, 1, hour=1).with_tzinfo(Some(eastern))
    check(amb, 'T')
    check(@tz.enfold(amb, fold=1), 'T')
  }
  let rng = { state: 20261002UL, }
  for _ in 0..<1500 {
    let ordinal = 1 + rng.next(@datetime.MAXORDINAL)
    let d = @datetime.Date::from_ordinal(ordinal)
    let dt = dt(
      d.year,
      d.month,
      d.day,
      hour=rng.next(24),
      minute=rng.next(60),
      second=rng.next(60),
      microsecond=rng.next(1000000),
    ).with_tzinfo(Some(zones[rng.next(zones.length())]))
    check(@tz.enfold(dt, fold=rng.next(2)), Int::unsafe_to_char(rng.next(128)))
  }
}
