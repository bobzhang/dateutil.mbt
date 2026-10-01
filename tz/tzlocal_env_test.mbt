// tzlocal tests that change the TZ environment variable (upstream
// TZEnvContext). `@datetime.tzset()` re-reads TZ on every backend (the C
// library on native, the internal/tzdata resolver elsewhere).

///|
/// Upstream `TZEnvContext`: run `f` with `TZ=tzval`, restoring it after.
fn with_tz_env(tzval : String, f : () -> Unit raise) -> Unit raise {
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
test "differential: tzlocal under TZ strings" {
  let groups : Map[String, Array[String]] = Map([])
  for rec in tzlocal_corpus {
    let key = rec.split("|").nth(1).unwrap().to_owned()
    match groups.get(key) {
      Some(a) => a.push(rec)
      None => groups[key] = [rec]
    }
  }
  for key, recs in groups {
    with_tz_env(key.view(start_offset=2).to_owned(), () => {
      let zone = @tz.tzlocal()
      check_corpus(recs, _ => zone)
    })
  }
}

///|
/// The TzFoldMixin suite with `tzlocal()` and TZ set per zone
/// (upstream `TzLocalNixTest`).
test "TzLocalNixTest: TzFoldMixin" {
  let old = @env.get_env_var("TZ")
  fold_mixin(
    name => {
      let tzval = match name {
        "Australia/Sydney" => "AEST-10AEDT,M10.1.0/2,M4.1.0/3"
        "America/Toronto" | "America/New_York" => "EST+5EDT,M3.2.0/2,M11.1.0/2"
        "Europe/London" => "GMT0BST,M3.5.0,M10.5.0"
        other => other
      }
      @env.set_env_var("TZ", tzval)
      @datetime.tzset()
      @tz.tzlocal()
    },
    restore=() => {
      match old {
        Some(v) => @env.set_env_var("TZ", v)
        None => @env.unset_env_var("TZ")
      }
      @datetime.tzset()
    },
  )
}

///|
let tz_est : String = "EST+5EDT,M3.2.0/2,M11.1.0/2"

///|
/// Upstream `_testTzFunc`: STD on 2015-02-01, DST on 2015-05-01.
fn check_tz_func(
  tzval : String,
  func : (@datetime.DateTime) -> String,
  std_val : String,
  dst_val : String,
) -> Unit raise {
  with_tz_env(tzval, () => {
    let dt1 = dt(2015, 2, 1, hour=12, tz=@tz.tzlocal()) // STD
    let dt2 = dt(2015, 5, 1, hour=12, tz=@tz.tzlocal()) // DST
    assert_eq(func(dt1), std_val)
    assert_eq(func(dt2), dst_val)
  })
}

///|
test "TzLocalNixTest.testTzNameDST / testTzNameUTC" {
  let f = (d : @datetime.DateTime) => name_str(d.tzname())
  check_tz_func(tz_est, f, "EST", "EDT")
  check_tz_func("UTC", f, "UTC", "UTC")
}

///|
test "TzLocalNixTest.testOffsetDST / testOffsetUTC" {
  let f = (d : @datetime.DateTime) => secs_str(d.utcoffset())
  check_tz_func(tz_est, f, "-18000", "-14400")
  check_tz_func("UTC", f, "0", "0")
}

///|
test "TzLocalNixTest.testDSTDST / testDSTUTC" {
  let f = (d : @datetime.DateTime) => secs_str(d.dst())
  check_tz_func(tz_est, f, "0", "3600")
  check_tz_func("UTC", f, "0", "0")
}

///|
test "TzLocalNixTest.testTimeOnly*" {
  with_tz_env("UTC", () => {
    let t = @datetime.Time::new(hour=13, minute=20, tzinfo=@tz.tzlocal())
    assert_eq(t.utcoffset(), Some(hours(0)))
    assert_eq(t.dst(), Some(hours(0)))
  })
  with_tz_env(tz_est, () => {
    let t = @datetime.Time::new(hour=13, minute=20, tzinfo=@tz.tzlocal())
    assert_eq(t.utcoffset(), None)
    assert_eq(t.dst(), None)
  })
}

///|
test "TzLocalNixTest.testUTCEquality / test_tzlocal_utc_equal" {
  for tzvar in ["UTC", "GMT0", "UTC0"] {
    with_tz_env(tzvar, () => {
      assert_true(@tz.tzlocal() == @tz.utc)
      assert_true(@tz.utc == @tz.tzlocal())
    })
  }
}

///|
test "test_tzlocal_utc_unequal" {
  for tzvar in ["Europe/London", "America/New_York", "GMT0BST", "EST5EDT"] {
    with_tz_env(tzvar, () => {
      assert_false(@tz.tzlocal() == @tz.utc)
      assert_false(@tz.utc == @tz.tzlocal())
    })
  }
}

///|
test "test_tzlocal_local_time_trim_colon" {
  with_tz_env(":/etc/localtime", () => assert_true(@tz.gettz() is Some(_)))
}

///|
test "test_tzlocal_offset_equal" {
  let cases = [
    ("EST5", @tz.tzoffset(Some("EST"), -18000)),
    ("GMT0", @tz.tzoffset(Some("GMT"), 0)),
    ("YAKT-9", @tz.tzoffset_delta(Some("YAKT"), hours(9))),
    ("JST-9", @tz.tzoffset_delta(Some("JST"), hours(9))),
  ]
  for case in cases {
    let (tzvar, tzoff) = case
    with_tz_env(tzvar, () => {
      // Including both to test both __eq__ and __ne__
      assert_true(@tz.tzlocal() == tzoff)
      assert_true(tzoff == @tz.tzlocal())
      assert_false(@tz.tzlocal() != tzoff)
    })
  }
}

///|
test "test_tzlocal_offset_unequal" {
  let cases = [
    ("EST5EDT", @tz.tzoffset(Some("EST"), -18000)),
    ("GMT0BST", @tz.tzoffset(Some("GMT"), 0)),
    ("EST5", @tz.tzoffset(Some("EST"), -14400)),
    ("YAKT-9", @tz.tzoffset_delta(Some("JST"), hours(9))),
    ("JST-9", @tz.tzoffset_delta(Some("YAKT"), hours(9))),
  ]
  for case in cases {
    let (tzvar, tzoff) = case
    with_tz_env(tzvar, () => {
      assert_true(@tz.tzlocal() != tzoff)
      assert_false(@tz.tzlocal() == tzoff)
      assert_false(tzoff == @tz.tzlocal())
    })
  }
}

///|
test "TzLocalTest (with a fixed local zone)" {
  with_tz_env("JST-9", () => {
    let tzl = @tz.tzlocal()
    // testInequalityFixedOffset
    let tzos = @tz.tzoffset_delta(Some("LST"), hours(9))
    let tzod = @tz.tzoffset_delta(Some("LDT"), hours(9))
    assert_false(tzl == tzos)
    assert_false(tzl == tzod)
    assert_true(tzl != tzos)
    assert_true(tzl != tzod)
  })
}

///|
test "TZTest.testTZSetDoesntCorrupt (tzlocal follows TZ)" {
  // Upstream checks that the parser is not confused after a tzset; the
  // parser lives elsewhere, so check that tzlocal follows TZ changes.
  with_tz_env("UTC", () => {
    let d = dt(2014, 7, 20, hour=12, minute=34, second=56, tz=@tz.tzlocal())
    inspect(d, content="2014-07-20 12:34:56+00:00")
  })
  with_tz_env("JST-9", () => {
    let d = dt(2014, 7, 20, hour=12, minute=34, second=56, tz=@tz.tzlocal())
    inspect(d, content="2014-07-20 12:34:56+09:00")
  })
}

///|
test "gettz honours TZ and tzlocal names" {
  with_tz_env("JST-9", () => {
    // gettz() with TZ set: a TZ string, parsed by tzstr
    let z = @tz.gettz().unwrap()
    inspect(z, content="tzstr('JST-9')")
    // a name of the local zone gives tzlocal() (and is not cached)
    let l1 = @tz.gettz(name="JST").unwrap()
    let l2 = @tz.gettz(name="JST").unwrap()
    inspect(l1, content="tzlocal()")
    assert_false(l1.is_same(l2))
  })
}

///|
test "tzlocal under TZ=Europe/London: 1941 British Summer Time in winter" {
  with_tz_env("Europe/London", () => {
    let d = dt(1941, 1, 15, hour=12, tz=@tz.tzlocal())
    inspect(d, content="1941-01-15 12:00:00+01:00")
    inspect(name_str(d.tzname()), content="BST")
    let d = dt(2024, 1, 15, hour=12, tz=@tz.tzlocal())
    inspect(d, content="2024-01-15 12:00:00+00:00")
    inspect(name_str(d.tzname()), content="GMT")
  })
}
