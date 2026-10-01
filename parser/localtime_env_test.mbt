// The parser recognises the local zone's names (`time.tzname`) on every
// backend: the system local time comes from libc on native and from the
// internal/tzdata resolver (honouring TZ) on wasm, wasm-gc and js.

///|
fn with_tz(tzval : String, f : () -> Unit raise) -> Unit raise {
  let old = @env.get_env_var("TZ")
  @env.set_env_var("TZ", tzval)
  @datetime.tzset()
  defer {
    match old {
      Some(v) => @env.set_env_var("TZ", v)
      None => @env.unset_env_var("TZ")
    }
    @datetime.tzset()
  }
  f()
}

///|
test "local zone names: BST under TZ=Europe/London" {
  with_tz("Europe/London", () => {
    let d = @parser.parse("2024-07-01 12:00 BST")
    inspect(d.isoformat(), content="2024-07-01T12:00:00+01:00")
    inspect(d.tzinfo is Some(z) && z.to_string() == "tzlocal()", content="true")
    let w = @parser.parse("2024-01-15 12:00 GMT")
    inspect(w.isoformat(), content="2024-01-15T12:00:00+00:00")
  })
}

///|
test "TestTZVar.test_parse_unambiguous_nonexistent_local" {
  // When dates are specified "EST" even when they should be "EDT" in the
  // local time zone, we should still assign the local time zone
  with_tz("EST+5EDT,M3.2.0/2,M11.1.0/2", () => {
    let dt_exp = @datetime.DateTime::new(
      2011,
      8,
      1,
      hour=12,
      minute=30,
      tzinfo=@tz.tzlocal(),
    )
    let dt = @parser.parse("2011-08-01T12:30 EST")
    assert_eq(dt.tzname(), Some("EDT"))
    assert_true(dt == dt_exp)
  })
}

///|
test "TestTZVar.test_tzlocal_in_gmt" {
  // GH #318
  with_tz("GMT0BST,M3.5.0,M10.5.0", () => {
    // This is an imaginary datetime in tz.tzlocal() but should still
    // parse using the GMT-as-alias-for-UTC rule
    let dt = @parser.parse("2004-05-01T12:00 GMT")
    let dt_exp = @datetime.DateTime::new(2004, 5, 1, hour=12, tzinfo=@tz.utc)
    assert_true(dt == dt_exp)
  })
}

///|
test "TestTZVar.test_tzlocal_parse_fold" {
  // One manifestion of GH #318
  with_tz("EST+5EDT,M3.2.0/2,M11.1.0/2", () => {
    let dt_exp = @tz.enfold(
      @datetime.DateTime::new(
        2011,
        11,
        6,
        hour=1,
        minute=30,
        tzinfo=@tz.tzlocal(),
      ),
      fold=1,
    )
    let dt = @parser.parse("2011-11-06T01:30 EST")
    assert_eq(dt.tzname(), dt_exp.tzname())
    assert_true(dt.replace(tzinfo=None) == dt_exp.replace(tzinfo=None))
    assert_eq(dt.fold, dt_exp.fold)
    assert_true(dt.astimezone(tz=@tz.utc) == dt_exp.astimezone(tz=@tz.utc))
  })
}

///|
test "local zone names: AEST/AEDT under a POSIX TZ string" {
  with_tz("AEST-10AEDT,M10.1.0,M4.1.0/3", () => {
    let d = @parser.parse("2024-01-15 12:00 AEDT")
    inspect(d.isoformat(), content="2024-01-15T12:00:00+11:00")
    let d = @parser.parse("2024-07-15 12:00 AEST")
    inspect(d.isoformat(), content="2024-07-15T12:00:00+10:00")
  })
}
