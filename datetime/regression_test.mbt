// Regression tests for issues found in Codex review round 1. Expected
// values come from CPython 3.13.

///|
test "date - timedelta ignores sub-day parts" {
  let d = @datetime.Date::new(2024, 1, 2)
  inspect(d.sub(@datetime.TimeDelta::new(seconds=1)), content="2024-01-02")
}

///|
test "timedelta multiplication and division" {
  inspect(
    @datetime.TimeDelta::new(microseconds=-1).checked_mul(2147483647),
    content="-1 day, 23:24:12.516353",
  )
  inspect(
    @datetime.TimeDelta::new(microseconds=5).mul_float(0.1).repr(),
    content="datetime.timedelta(microseconds=1)",
  )
  inspect(
    @datetime.TimeDelta::new(days=3, microseconds=7).mul_float(1.1).repr(),
    content="datetime.timedelta(days=3, seconds=25920, microseconds=8)",
  )
  inspect(
    @datetime.max_timedelta.mul_float(0.5).repr(),
    content="datetime.timedelta(days=500000000)",
  )
  inspect(
    @datetime.max_timedelta.div_int(2).repr(),
    content="datetime.timedelta(days=500000000)",
  )
  inspect(
    @datetime.TimeDelta::new(seconds=-7).div_int(2).repr(),
    content="datetime.timedelta(days=-1, seconds=86396, microseconds=500000)",
  )
  inspect(
    @datetime.TimeDelta::new(seconds=-7).floor_div(
      @datetime.TimeDelta::new(seconds=2),
    ),
    content="-4",
  )
  inspect(
    @datetime.TimeDelta::from_float(microseconds=1.0e19).repr(),
    content="datetime.timedelta(days=115740740, seconds=64000)",
  )
  try
    @datetime.TimeDelta::new(seconds=1).ratio(@datetime.zero_timedelta)
  catch {
    e => inspect(e, content="ValueError: division by zero")
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "strftime pads %Y and %G" {
  let d = @datetime.DateTime::new(1, 1, 1)
  inspect(d.strftime("%Y|%G|%-Y"), content="0001|0001|1")
  inspect(@datetime.Date::new(999, 5, 1).strftime("%Y"), content="0999")
}

///|
test "calendar helpers for far years" {
  inspect(@datetime.weekday_of(6000000, 1, 1), content="5")
  debug_inspect(@datetime.monthrange(-1, 2), content="(0, 28)")
  // 400-year cycles keep timegm exact
  inspect(
    @datetime.timegm(12000, 3, 1, 1, 2, 3) -
    @datetime.timegm(11600, 3, 1, 1, 2, 3),
    content="12622780800",
  )
}

///|
test "timezone(timedelta(0)) is timezone.utc" {
  let z = @datetime.Tz::fixed(@datetime.zero_timedelta)
  assert_true(z.is_same(@datetime.utc))
  inspect(z, content="datetime.timezone.utc")
  let named = @datetime.Tz::fixed(
    @datetime.TimeDelta::new(hours=1),
    name="a\u{a0}b\u{200b}c'",
  )
  inspect(
    named,
    content=(
      #|datetime.timezone(datetime.timedelta(seconds=3600), "a\xa0b\u200bc'")
    ),
  )
}

///|
test "time equality uses full offsets" {
  let t1 = @datetime.Time::new(
    hour=12,
    tzinfo=@datetime.Tz::fixed(@datetime.TimeDelta::new(seconds=30)),
  )
  let t2 = @datetime.Time::new(hour=12, tzinfo=@datetime.utc)
  assert_true(t1 != t2)
  assert_true(t1 < t2)
}
