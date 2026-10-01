///|
fn check_date(
  y : Int,
  m : Int,
  d : Int,
  ordinal~ : Int,
  weekday~ : Int,
  iso~ : (Int, Int, Int),
  yday~ : Int,
) -> Unit raise {
  let date = @datetime.Date::new(y, m, d)
  assert_eq(date.to_ordinal(), ordinal)
  assert_eq(@datetime.Date::from_ordinal(ordinal), date)
  assert_eq(date.weekday(), weekday)
  assert_eq(date.isocalendar(), iso)
  assert_eq(@datetime.Date::from_isocalendar(iso.0, iso.1, iso.2), date)
  assert_eq(date.timetuple().yday, yday)
}

///|
fn check_td(
  td : @datetime.TimeDelta,
  str : String,
  repr : String,
  total : Double,
) -> Unit raise {
  assert_eq(td.to_string(), str)
  assert_eq(td.repr(), repr)
  assert_eq(td.total_seconds(), total)
}

///|
fn check_add(
  dt : @datetime.DateTime,
  td : @datetime.TimeDelta,
  expected : String?,
) -> Unit raise {
  match expected {
    Some(s) => {
      let r = dt.add(td)
      assert_eq(r.to_string(), s)
      assert_eq(r.sub(td), dt)
      assert_eq(r.diff(dt), td)
    }
    None =>
      try dt.add(td) catch {
        @datetime.OverflowError(_) => ()
        e => fail("unexpected \{e}")
      } noraise {
        r => fail("expected overflow, got \{r}")
      }
  }
}

///|
fn check_diff(
  a : @datetime.DateTime,
  b : @datetime.DateTime,
  repr : String,
  cmp : Int,
) -> Unit raise {
  assert_eq(a.diff(b).repr(), repr)
  assert_eq(a.compare(b), cmp)
  assert_eq(a == b, cmp == 0)
}

///|
fn check_fmt(
  dt : @datetime.DateTime,
  fmt : String,
  expected : String,
  str : String,
  repr : String,
  iso : String,
) -> Unit raise {
  assert_eq(dt.strftime(fmt), expected)
  assert_eq(dt.to_string(), str)
  assert_eq(dt.repr(), repr)
  assert_eq(dt.isoformat(), iso)
}

///|
fn check_ts(t : Double, expected : String) -> Unit raise {
  assert_eq(@datetime.DateTime::utc_from_timestamp(t).to_string(), expected)
  let aware = @datetime.DateTime::from_timestamp(t, tz=@datetime.utc)
  assert_eq(aware.to_string(), expected + "+00:00")
}
