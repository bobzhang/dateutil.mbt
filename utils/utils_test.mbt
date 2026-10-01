// Port of dateutil tests/test_utils.py (clock-independent tests). The
// freezegun-based `today` tests are in utils_wbtest.mbt. `nyc()` is
// defined per target in nyc_fs_test.mbt / nyc_nofs_test.mbt.

///|
test "test_utils_default_tz_info_naive" {
  let ny = nyc()
  let dt = @datetime.DateTime::new(2014, 9, 14, hour=9, minute=30)
  let r = @utils.default_tzinfo(dt, ny)
  assert_true(r.tzinfo is Some(z) && z.is_same(ny))
}

///|
test "test_utils_default_tz_info_aware" {
  let dt = @datetime.DateTime::new(
    2014,
    9,
    14,
    hour=9,
    minute=30,
    tzinfo=@tz.utc,
  )
  let r = @utils.default_tzinfo(dt, nyc())
  assert_true(r.tzinfo is Some(z) && z.is_same(@tz.utc))
}

///|
test "test_utils_within_delta" {
  let d1 = @datetime.DateTime::new(
    2016,
    1,
    1,
    hour=12,
    minute=14,
    second=1,
    microsecond=9,
  )
  let d2 = d1.replace(microsecond=15)
  assert_true(@utils.within_delta(d1, d2, @datetime.TimeDelta::new(seconds=1)))
  assert_false(
    @utils.within_delta(d1, d2, @datetime.TimeDelta::new(microseconds=1)),
  )
}

///|
test "test_utils_within_delta_with_negative_delta" {
  let d1 = @datetime.DateTime::new(2016, 1, 1)
  let d2 = @datetime.DateTime::new(2015, 12, 31)
  assert_true(@utils.within_delta(d2, d1, @datetime.TimeDelta::new(days=-1)))
}

///|
test "within_delta: naive vs aware raises TypeError" {
  let d1 = @datetime.DateTime::new(2016, 1, 1)
  let d2 = d1.with_tzinfo(Some(@tz.utc))
  try @utils.within_delta(d1, d2, @datetime.TimeDelta::new(days=1)) catch {
    @datetime.TypeError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected TypeError")
  }
}

///|
test "within_delta: -timedelta.max overflows, timedelta.min is fine" {
  let d = @datetime.DateTime::new(2000, 1, 1)
  try @utils.within_delta(d, d, @datetime.max_timedelta) catch {
    @datetime.OverflowError(msg) =>
      inspect(msg, content="days=-1000000000; must have magnitude <= 999999999")
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected OverflowError")
  }
  assert_true(@utils.within_delta(d, d, @datetime.min_timedelta))
}

///|
test "within_delta: aware datetimes in different zones" {
  let d1 = @datetime.DateTime::new(2016, 1, 1, hour=12, tzinfo=@tz.utc)
  let d2 = @datetime.DateTime::new(2016, 1, 1, hour=7, tzinfo=nyc())
  assert_true(@utils.within_delta(d1, d2, @datetime.TimeDelta::new()))
}

///|
test "today: real clock (midnight, consistent with now)" {
  let before = @datetime.DateTime::now()
  let t = @utils.today()
  let after = @datetime.DateTime::now()
  assert_true(t.tzinfo is None)
  assert_eq((t.hour, t.minute, t.second, t.microsecond), (0, 0, 0, 0))
  assert_true(t.date() == before.date() || t.date() == after.date())
  let t = @utils.today(tzinfo=@tz.utc)
  assert_true(t.tzinfo is Some(z) && z.is_same(@tz.utc))
  assert_eq((t.hour, t.minute, t.second, t.microsecond), (0, 0, 0, 0))
}
