// Upstream tests that need tz.tzstr / tz.tzlocal.

///|
test "test_parser::TestTzinfoInputTypes::test_valid_tzinfo_unicode_input" {
  let tzinfos = @parser.Table({ "UTC": TzString("UTC+0") })
  let expected = dt(2014, 1, 19, hour=9).with_tzinfo(Some(@tz.tzstr("UTC+0")))
  let res = @parser.parse("2014 January 19 09:00 UTC", tzinfos~)
  assert_eq(res, expected)
  assert_true(same_tz(res, expected))
}

///|
test "test_parser::TestTzinfoInputTypes::test_valid_tzinfo_callable_input" {
  let tzinfos = @parser.Callback((_, _) => TzString("UTC+0"))
  let expected = dt(2014, 1, 19, hour=9).with_tzinfo(Some(@tz.tzstr("UTC+0")))
  let res = @parser.parse("2014 January 19 09:00 UTC", tzinfos~)
  assert_eq(res, expected)
  assert_true(same_tz(res, expected))
}

///|
test "local zone names resolve to tzlocal()" {
  let (std, _) = @datetime.local_zone().tzname
  // Only names the parser treats as zone names (<= 5 ASCII capitals or a
  // UTCZONE entry) reach the tzlocal() branch.
  if std.length() > 0 &&
    std.length() <= 5 &&
    std.iter().all(c => c is ('A'..='Z')) {
    let res = @parser.parse("2003-01-15 10:00 \{std}")
    guard res.tzinfo is Some(z) else { fail("expected an aware result") }
    if std == "UTC" || std == "GMT" {
      // may fall back to tz.UTC when the local zone reports another name
      assert_true(z == @tz.tzlocal() || z.is_same(@tz.utc))
    } else {
      assert_eq(z, @tz.tzlocal())
    }
  }
}
