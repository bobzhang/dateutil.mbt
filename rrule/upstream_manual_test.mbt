// Hand-ported upstream tests (tests/test_rrule.py) that the generator does
// not translate. Skipped tests are listed in PORTING.md.

///|
test "RRuleTest.testBadUntilCountRRule" {
  // Python only emits a DeprecationWarning; the rule is still created.
  let rr = @rrule.Rrule::new(
    Daily,
    dtstart=dt(1997, 9, 2, h=9),
    count=3,
    until=dt(1997, 9, 4, h=9),
  )
  assert_eq(rr.to_array(), [
    dt(1997, 9, 2, h=9),
    dt(1997, 9, 3, h=9),
    dt(1997, 9, 4, h=9),
  ])
}

///|
fn set_with_two_rules(cache : Bool) -> @rrule.RruleSet raise {
  let rrset = @rrule.RruleSet::new(cache~)
  rrset.rrule(
    @rrule.Rrule::new(
      Yearly,
      count=2,
      byweekday=[@rrule.th],
      dtstart=dt(1983, 4, 1),
    ),
  )
  rrset.rrule(
    @rrule.Rrule::new(
      Weekly,
      count=4,
      byweekday=[@rrule.fr],
      dtstart=dt(1991, 6, 3),
    ),
  )
  rrset
}

///|
test "RRuleSetTest.testSetRRuleCount" {
  for cache in [true, false] {
    let rrset = set_with_two_rules(cache)
    // Check the length twice - first one sets a cache, second reads it
    assert_eq(rrset.count(), 6)
    assert_eq(rrset.count(), 6)
    // This should invalidate the cache and force an update
    rrset.rrule(@rrule.Rrule::new(Monthly, count=3, dtstart=dt(1994, 1, 3)))
    assert_eq(rrset.count(), 9)
    assert_eq(rrset.count(), 9)
  }
}

///|
test "RRuleSetTest.testSetRDateCount" {
  for cache in [true, false] {
    let rrset = set_with_two_rules(cache)
    assert_eq(rrset.count(), 6)
    assert_eq(rrset.count(), 6)
    rrset.rdate(dt(1993, 2, 14))
    assert_eq(rrset.count(), 7)
    assert_eq(rrset.count(), 7)
  }
}

///|
test "RRuleSetTest.testSetExRuleCount" {
  for cache in [true, false] {
    let rrset = set_with_two_rules(cache)
    assert_eq(rrset.count(), 6)
    assert_eq(rrset.count(), 6)
    rrset.exrule(
      @rrule.Rrule::new(Weekly, count=2, interval=2, dtstart=dt(1991, 6, 14)),
    )
    assert_eq(rrset.count(), 4)
    assert_eq(rrset.count(), 4)
  }
}

///|
test "RRuleSetTest.testSetExDateCount" {
  for cache in [true, false] {
    let rrset = set_with_two_rules(cache)
    assert_eq(rrset.count(), 6)
    assert_eq(rrset.count(), 6)
    rrset.exdate(dt(1991, 6, 28))
    assert_eq(rrset.count(), 5)
    assert_eq(rrset.count(), 5)
  }
}

///|
test "test_generated_aware_dtstart" {
  // Upstream freezes the clock; here we only check that the generated
  // dtstart is "now" in until's zone, truncated to the second.
  let utc = @tz.tzutc()
  let before = @datetime.DateTime::now(tz=utc).replace(microsecond=0)
  let until = before.add(@datetime.TimeDelta::new(hours=3))
  let rule_without_dtstart = @rrule.Rrule::new(Hourly, until~)
  let after = @datetime.DateTime::now(tz=utc)
  let first = rule_without_dtstart.get(0).unwrap()
  assert_true(first.tzinfo is Some(z) && z.is_same(utc))
  assert_true(first.microsecond == 0 && first >= before && first <= after)
  let rule_with_dtstart = @rrule.Rrule::new(Hourly, dtstart=first, until~)
  assert_eq(rule_without_dtstart.to_array(), rule_with_dtstart.to_array())
}

///|
test "WeekdayTest.testInvalidNthWeekday" {
  expect_value_error(() => ignore(@rrule.nth(@rrule.fr, 0)))
}

///|
test "WeekdayTest.testWeekdayCallable" {
  // Calling a weekday instance generates a new weekday instance with the
  // value of n changed.
  assert_eq(@rrule.nth(@rrule.mo, 1), @rrule.weekday(0, n=1))
  // Calling a weekday instance with the identical n returns the original
  // object
  let fr_3 = @rrule.weekday(4, n=3)
  assert_true(physical_equal(@rrule.nth(fr_3, 3), fr_3))
}

///|
test "WeekdayTest.testWeekdayEquality" {
  // Two weekday objects are not equal if they have different values for n
  assert_not_eq(@rrule.th, @rrule.nth(@rrule.th, -1))
  assert_not_eq(@rrule.nth(@rrule.sa, 3), @rrule.nth(@rrule.sa, 2))
}

///|
test "WeekdayTest.testWeekdayEqualitySubclass" {
  // Duck-typed equality with foreign classes has no MoonBit analogue; the
  // base `@datetime.Weekday` (Python `_common.weekday`) is the same type.
  assert_eq(@rrule.tu, @datetime.Weekday::new(1))
  assert_not_eq(@rrule.nth(@rrule.tu, 3), @datetime.Weekday::new(1))
  assert_eq(@rrule.nth(@rrule.we, 3), @datetime.Weekday::new(2, n=3))
  assert_not_eq(@rrule.nth(@rrule.we, 2), @datetime.Weekday::new(2, n=3))
}

///|
test "WeekdayTest.testWeekdayReprNoN" {
  let no_n_reprs = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
  let no_n_wdays = [
    @rrule.mo, @rrule.tu, @rrule.we, @rrule.th, @rrule.fr, @rrule.sa, @rrule.su,
  ]
  for i, repstr in no_n_reprs {
    assert_eq(no_n_wdays[i].to_string(), repstr)
  }
}

///|
test "WeekdayTest.testWeekdayReprWithN" {
  let with_n_reprs = ["WE(+1)", "TH(-2)", "SU(+3)"]
  let with_n_wdays = [
    @rrule.nth(@rrule.we, 1),
    @rrule.nth(@rrule.th, -2),
    @rrule.nth(@rrule.su, 3),
  ]
  for i, repstr in with_n_reprs {
    assert_eq(with_n_wdays[i].to_string(), repstr)
  }
}

///|
test "RRuleTest.testStrWithTZIDCallableFailure" {
  let rrstr = "DTSTART;TZID=America/New_York:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=3"
  let tzinfos : (String) -> @datetime.Tz? raise = tzstr => {
    if tzstr == "America/New_York" {
      raise Failure("Invalid!")
    }
    None
  }
  try @rrule.rrulestr(rrstr, tzids=Callback(tzinfos)) catch {
    Failure(msg) => assert_eq(msg, "Invalid!")
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected TzInfoError")
  }
}

///|
test "RRuleTest.testStrWithTZIDCallable" {
  let rrstr = "DTSTART;TZID=UTC+04:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=3"
  let tz = @tz.tzstr("UTC+04")
  let parse_tzstr : (String) -> @datetime.Tz? raise = tzstr => {
    Some(@tz.tzstr(tzstr))
  }
  let rr = @rrule.rrulestr(rrstr, tzids=Callback(parse_tzstr))
  let exp = [
    dt(1997, 9, 2, h=9, tz~),
    dt(1998, 9, 2, h=9, tz~),
    dt(1999, 9, 2, h=9, tz~),
  ]
  assert_eq(rr.to_array(), exp)
}
