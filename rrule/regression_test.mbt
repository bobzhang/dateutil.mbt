// Edge cases checked against python-dateutil by hand (mostly from a Codex
// review of the port).

///|
test "weekly period crossing into year 10000 yields before failing" {
  let r = @rrule.Rrule::new(
    Weekly,
    dtstart=dt(9999, 12, 27),
    byweekday=[
      @rrule.mo, @rrule.tu, @rrule.we, @rrule.th, @rrule.fr, @rrule.sa, @rrule.su,
    ],
    count=1,
  )
  assert_eq(r.to_array(), [dt(9999, 12, 27)])
  let r = r.replace(count=None, until=Some(dt(9999, 12, 27)))
  assert_eq(r.to_array(), [dt(9999, 12, 27)])
  // without a bound, Python raises when it reaches 10000-01-01
  let r = r.replace(until=None)
  expect_value_error(() => ignore(r.to_array()))
}

///|
test "naive/aware mix in until comparison raises TypeError" {
  // A zone whose utcoffset is None counts as aware for the construction
  // check but compares like a naive datetime.
  let none_tz = @datetime.Tz::new(NoOffset::{ })
  let r = @rrule.Rrule::new(
    Daily,
    dtstart=dt(2024, 1, 1, tz=none_tz),
    until=dt(2024, 1, 2, tz=@tz.tzutc()),
  )
  try r.to_array() catch {
    @datetime.TypeError(_) => ()
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected TypeError")
  }
}

///|
priv struct NoOffset {}

///|
impl @datetime.TzInfo for NoOffset with fn utcoffset(_, _) {
  None
}

///|
impl @datetime.TzInfo for NoOffset with fn dst(_, _) {
  None
}

///|
impl @datetime.TzInfo for NoOffset with fn tzname(_, _) {
  None
}

///|
impl @datetime.TzInfo for NoOffset with fn repr(_) {
  "NoOffset()"
}

///|
test "huge intervals" {
  let start = dt(2024, 1, 1)
  assert_eq(
    @rrule.Rrule::new(Yearly, dtstart=start, interval=2147483647, count=2).to_array(),
    [start],
  )
  assert_eq(
    @rrule.Rrule::new(Monthly, dtstart=start, interval=2147483647, count=2).to_array(),
    [start],
  )
  assert_eq(
    @rrule.Rrule::new(Daily, dtstart=start, interval=2147483647, count=2).to_array(),
    [start],
  )
  assert_eq(
    @rrule.Rrule::new(Weekly, dtstart=start, interval=2147483647, count=2).to_array(),
    [start],
  )
  assert_eq(
    @rrule.Rrule::new(Hourly, dtstart=start, interval=2147483647, count=2).to_array(),
    [start],
  )
}

///|
test "negative count and intervals" {
  let start = dt(2024, 1, 1)
  assert_eq(
    @rrule.Rrule::new(Daily, dtstart=start, count=-2147483648).to_array(),
    [],
  )
  // Python: ValueError: not enough values to unpack (expected 2, got 0)
  expect_value_error(() => {
    ignore(
      @rrule.Rrule::new(Monthly, dtstart=start, interval=-1, count=2).to_array(),
    )
  })
  // Python: ValueError: day is out of range for month
  expect_value_error(() => {
    ignore(
      @rrule.Rrule::new(Daily, dtstart=start, interval=-1, count=2).to_array(),
    )
  })
  // Python: ValueError: year -3 is out of range
  expect_value_error(() => {
    ignore(
      @rrule.Rrule::new(Yearly, dtstart=dt(2, 1, 1), interval=-5, count=2).to_array(),
    )
  })
}

///|
test "slices with large steps" {
  let r = @rrule.Rrule::new(Daily, dtstart=dt(2024, 1, 1), count=3)
  assert_eq(r.slice(start=1, step=2147483647), [dt(2024, 1, 2)])
  let r = @rrule.Rrule::new(Daily, dtstart=dt(2024, 1, 1), count=3, cache=true)
  ignore(r.to_array())
  assert_eq(r.slice(start=1, step=2147483647), [dt(2024, 1, 2)])
  assert_eq(r.slice(start=-1, step=-2147483647), [dt(2024, 1, 3)])
}

///|
test "rrulestr int() accepts Unicode decimal digits" {
  let r = @rrule.rrulestr(
    "FREQ=DAILY;COUNT=٢;INTERVAL=1_0",
    dtstart=dt(2024, 1, 1),
  )
  assert_eq(r.to_array(), [dt(2024, 1, 1), dt(2024, 1, 11)])
}

///|
test "islice quirks of __getitem__" {
  let r = @rrule.Rrule::new(Daily, dtstart=dt(2024, 1, 1), count=3)
  // `stop or sys.maxsize`: stop=0 means no limit
  assert_eq(r.slice(stop=0).length(), 3)
  // negative indices are rejected by islice
  expect_value_error(() => ignore(r.slice(start=-1)))
  // except with a negative step, which slices the full list
  assert_eq(r.slice(step=-1), [dt(2024, 1, 3), dt(2024, 1, 2), dt(2024, 1, 1)])
  assert_eq(r.get(-1), Some(dt(2024, 1, 3)))
  assert_eq(r.get(3), None)
}
