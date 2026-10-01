// Edge cases found in review; expected values verified against CPython +
// python-dateutil.

///|
fn kind(f : () -> String raise) -> String {
  f() catch {
    @datetime.ValueError(m) => "ValueError: \{m}"
    @datetime.OverflowError(_) => "OverflowError"
    e => "unexpected: \{e}"
  }
}

///|
test "timedelta leftover uses exact C round()" {
  // datetime(2000,1,1) + relativedelta(seconds=1e-6,
  //   microseconds=0.49999999999999994) -> ...0, 1)
  let rd = RelativeDelta::from_float(
    seconds=1.0e-6,
    microseconds=0.49999999999999994,
  )
  inspect(
    rd.add_to_datetime(dt(2000, 1, 1)).repr(),
    content="datetime.datetime(2000, 1, 1, 0, 0, 0, 1)",
  )
}

///|
test "huge weekday occurrence overflows instead of wrapping" {
  let rd = RelativeDelta::new(weekday=mo.nth(Some(613566758)))
  inspect(
    kind(() => rd.add_to_datetime(dt(2000, 1, 1)).repr()),
    content="OverflowError",
  )
}

///|
test "month normalization near Int bounds" {
  inspect(
    RelativeDelta::new(months=-2147483648),
    content="relativedelta(years=-1.78957e+08, months=-8)",
  )
  inspect(
    RelativeDelta::from_float(months=3.0e9),
    content="relativedelta(years=+2.5e+08)",
  )
  // Python gives years=2147483648 (unbounded int); we raise OverflowError.
  inspect(
    kind(() => RelativeDelta::new(years=2147483647, months=12).repr()),
    content="OverflowError",
  )
}

///|
test "absolute year plus relative years beyond Int" {
  let rd = RelativeDelta::new(year=-2147483648, years=-2147481648)
  inspect(
    kind(() => rd.add_to_datetime(dt(2000, 1, 1)).repr()),
    content="OverflowError",
  )
}

///|
test "normalized() rejects non-finite fields" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  inspect(
    kind(() => RelativeDelta::from_float(days=nan).normalized().repr()),
    content="ValueError: cannot convert float NaN to integer",
  )
  inspect(
    kind(() => RelativeDelta::from_float(days=inf).normalized().repr()),
    content="OverflowError",
  )
  inspect(
    kind(() => RelativeDelta::from_float(hours=inf).normalized().repr()),
    content="ValueError: cannot convert float NaN to integer",
  )
}

///|
test "set_weeks with large day counts" {
  let r = RelativeDelta::from_float(days=3.0e9)
  r.set_weeks(0)
  assert_eq(r.days, 4.0)
}

///|
test "subtracting a delta whose negation overflows raises" {
  // datetime(2024, 1, 1) - relativedelta(years=-2**31) -> OverflowError
  let rd = RelativeDelta::new(years=-2147483648)
  inspect(
    kind(() => rd.sub_from_datetime(dt(2024, 1, 1)).repr()),
    content="OverflowError",
  )
  inspect(
    kind(() => {
      ignore(rd.sub_from_date(@datetime.Date::new(2024, 1, 1)))
      "ok"
    }),
    content="OverflowError",
  )
  // date(2024, 1, 1) - relativedelta(months=-2**31) -> year 178958994 ValueError
  inspect(
    kind(() => {
      ignore(
        RelativeDelta::new(months=-2147483648).sub_from_date(
          @datetime.Date::new(2024, 1, 1),
        ),
      )
      "ok"
    }),
    content="ValueError: year 178958994 is out of range",
  )
}

///|
test "subtraction does not materialise -rd (Codex fixes review)" {
  // Python: date(2024,1,1) - relativedelta(years=-2**31, year=-(2**31-1))
  let rd = @relativedelta.RelativeDelta::new(
    years=-2147483648,
    year=-2147483647,
  )
  inspect(
    rd.sub_from_date(@datetime.Date::new(2024, 1, 1)),
    content="0001-01-01",
  )
  // leapdays is not negated; fractional days and time fields are
  let rd2 = @relativedelta.RelativeDelta::from_float(
    months=1.0,
    days=1.5,
    leapdays=3,
    hours=2.0,
  )
  inspect(
    rd2.sub_from_datetime(@datetime.DateTime::new(2024, 1, 31, hour=10)),
    content="2023-12-29 20:00:00",
  )
  let rd3 = @relativedelta.RelativeDelta::new(years=-1, months=-11, leapdays=1)
  inspect(
    rd3.sub_from_date(@datetime.Date::new(2024, 3, 31)),
    content="2026-02-28",
  )
}
