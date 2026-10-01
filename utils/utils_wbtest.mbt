// The freezegun-based tests of dateutil tests/test_utils.py. freezegun is
// not available, so `today` is exercised through `today_with` and a fake
// `datetime.now` that mirrors freezegun's `FakeDatetime.now`:
//   now(None) = frozen + tz_offset
//   now(tz)   = tz.fromutc(frozen.replace(tzinfo=tz)) + tz_offset
// where `frozen` is the (naive, UTC) frozen instant.

///|
fn frozen_now(
  frozen : @datetime.DateTime,
  tz_offset? : Int = 0,
) -> (@datetime.Tz?) -> @datetime.DateTime {
  let off = @datetime.TimeDelta::new(hours=tz_offset)
  tz => {
    try! (match tz {
      None => frozen.add(off)
      Some(z) => z.fromutc(frozen.with_tzinfo(Some(z))).add(off)
    })
  }
}

///|
test "test_utils_today" {
  let now = frozen_now(
    @datetime.DateTime::new(
      2014,
      12,
      15,
      hour=1,
      minute=21,
      second=33,
      microsecond=4003,
    ),
  )
  assert_eq(today_with(now, None), @datetime.DateTime::new(2014, 12, 15))
}

///|
test "test_utils_today_tz_info" {
  // NYC = tz.gettz("America/New_York") is not available; EST (its
  // December offset) stands in.
  let nyc = @tz.tzoffset(Some("EST"), -18000)
  let now = frozen_now(
    @datetime.DateTime::new(2014, 12, 15, hour=12),
    tz_offset=5,
  )
  let r = today_with(now, Some(nyc))
  assert_eq(r, @datetime.DateTime::new(2014, 12, 15, tzinfo=nyc))
  assert_true(r.tzinfo is Some(z) && z.is_same(nyc))
}

///|
test "test_utils_today_tz_info_different_day" {
  let now = frozen_now(
    @datetime.DateTime::new(2014, 12, 15, hour=23),
    tz_offset=5,
  )
  let r = today_with(now, Some(@tz.utc))
  assert_eq(r, @datetime.DateTime::new(2014, 12, 16, tzinfo=@tz.utc))
  assert_true(r.tzinfo is Some(z) && z.is_same(@tz.utc))
}
