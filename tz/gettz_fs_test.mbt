// gettz/tzfile tests reading the system zoneinfo database (backends with a
// file system: native and js). Upstream GettzTest and friends.

///|
fn sys_zone(name : String) -> @datetime.Tz raise {
  guard @tz.gettz(name~) is Some(z) else { fail("gettz(\{name}) is None") }
  z
}

///|
test "GettzTest: TzFoldMixin" {
  fold_mixin(sys_zone)
}

///|
test "GettzTest.testGettz / testGetTzEquality / testGettzCacheTzFile" {
  let u = sys_zone("UTC")
  ignore(u.to_string())
  assert_eq(sys_zone("UTC"), sys_zone("UTC"))
  let nyc1 = sys_zone("America/New_York")
  let nyc2 = sys_zone("America/New_York")
  assert_true(nyc1.is_same(nyc2))
  inspect(nyc1, content="tzfile('/usr/share/zoneinfo/America/New_York')")
}

///|
test "GettzTest.testGettzCacheTzLocal" {
  let local1 = @tz.gettz()
  let local2 = @tz.gettz()
  assert_true(local1 is Some(_) && local2 is Some(_))
  assert_false(@datetime.same_tz(local1, local2))
}

///|
test "test_gettz_cache_clear" {
  let nyc1 = sys_zone("America/New_York")
  @tz.gettz_cache_clear()
  let nyc2 = sys_zone("America/New_York")
  assert_false(nyc1.is_same(nyc2))
  assert_eq(nyc1, nyc2)
  // set_cache_size is accepted (it has no observable effect here)
  @tz.gettz_set_cache_size(2)
  @tz.gettz_set_cache_size(8)
  assert_true(sys_zone("America/New_York").is_same(nyc2))
}

///|
test "GettzTest.testTimeOnlyGettz*" {
  let tz_get = sys_zone("Europe/Minsk")
  let t = @datetime.Time::new(hour=13, minute=20, tzinfo=tz_get)
  assert_eq(t.utcoffset(), None)
  assert_eq(t.dst(), None)
  assert_eq(t.tzname(), None)
  assert_eq(t.strftime("%H%M%Z"), "1320")
}

///|
test "GettzTest.testPortugalDST" {
  let portugal = sys_zone("Portugal")
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
test "test_samoa_transition (system data)" {
  let apia = sys_zone("Pacific/Apia")
  let d = dt(2011, 12, 29, hour=23, minute=59, tz=apia)
  assert_eq(d.utcoffset(), Some(hours(-10)))
  let dt_after = d
    .astimezone(tz=@tz.utc)
    .add(@datetime.TimeDelta::new(minutes=1))
    .astimezone(tz=apia)
  assert_eq(dt_after, dt(2011, 12, 31, tz=apia))
  assert_eq(dt_after.utcoffset(), Some(hours(14)))
}

///|
test "DatetimeExistsTest / DatetimeAmbiguousTest (system data)" {
  let syd = sys_zone("Australia/Sydney")
  let est = sys_zone("US/Eastern")
  assert_false(@tz.datetime_exists(dt(2012, 10, 7, hour=2, minute=30), tz=syd))
  assert_true(@tz.datetime_exists(dt(2012, 10, 7, hour=10, minute=30, tz=syd)))
  let d = dt(2012, 10, 7, hour=2, minute=30, tz=est)
  assert_false(@tz.datetime_exists(d, tz=syd))
  assert_true(
    @tz.datetime_ambiguous(dt(2011, 11, 6, hour=1, minute=30), tz=est),
  )
  assert_false(
    @tz.datetime_ambiguous(dt(2011, 11, 6, hour=4, minute=30, tz=est)),
  )
}

///|
test "ImaginaryDateTest (system data)" {
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
    (
      "America/New_York",
      dt(2017, 3, 12, hour=2, minute=30),
      dt(2017, 3, 12, hour=3, minute=30),
    ),
  ]
  for case in cases {
    let (name, d, expected) = case
    let tzi = sys_zone(name)
    assert_eq(
      @tz.resolve_imaginary(d.with_tzinfo(Some(tzi))),
      expected.with_tzinfo(Some(tzi)),
    )
  }
}

///|
test "gettz name forms" {
  // absolute paths, with and without the leading ':'
  let lon = @tz.gettz(name="/usr/share/zoneinfo/Europe/London").unwrap()
  inspect(lon, content="tzfile('/usr/share/zoneinfo/Europe/London')")
  let lon2 = @tz.gettz(name=":/usr/share/zoneinfo/Europe/London").unwrap()
  inspect(lon2, content="tzfile('/usr/share/zoneinfo/Europe/London')")
  assert_eq(lon, sys_zone("Europe/London"))
  assert_true(@tz.gettz(name=":Europe/London").unwrap() == lon)
  // a missing absolute path is None; a non-zone file raises ValueError
  assert_true(@tz.gettz(name="/nonexistent/zone") is None)
  try @tz.gettz(name="/etc/hosts") catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
  // spaces are looked up as underscores
  inspect(
    @tz.gettz(name="America/New York").unwrap(),
    content="tzfile('/usr/share/zoneinfo/America/New_York')",
  )
  // a zone file name takes precedence over a TZ string
  inspect(sys_zone("EST5EDT"), content="tzfile('/usr/share/zoneinfo/EST5EDT')")
  // tzfile(path)
  let u = @tz.tzfile("/usr/share/zoneinfo/UTC")
  inspect(u, content="tzfile('/usr/share/zoneinfo/UTC')")
  assert_eq(dt(2000, 1, 1, tz=u).utcoffset(), Some(hours(0)))
  try @tz.tzfile("/nonexistent/zone") catch {
    @tz.IOError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected IOError")
  }
}
