// Port of dateutil tests/test_relativedelta.py. Test titles keep the
// upstream names. Skipped tests are listed in PORTING.md.

///|
using @relativedelta {type RelativeDelta, mo, tu, we, fr, su}

///|
fn dt(
  y : Int,
  m : Int,
  d : Int,
  h? : Int = 0,
  mi? : Int = 0,
  s? : Int = 0,
  us? : Int = 0,
) -> @datetime.DateTime {
  @datetime.DateTime::new(y, m, d, hour=h, minute=mi, second=s, microsecond=us) catch {
    e => abort(e.to_string())
  }
}

///|
fn date(y : Int, m : Int, d : Int) -> @datetime.Date {
  @datetime.Date::new(y, m, d) catch {
    e => abort(e.to_string())
  }
}

///|
fn now() -> @datetime.DateTime {
  dt(2003, 9, 17, h=20, mi=54, s=47, us=282310)
}

///|
fn today() -> @datetime.Date {
  date(2003, 9, 17)
}

///|
/// `date + rd` expected to stay a date.
fn add_d(d : @datetime.Date, rd : RelativeDelta) -> @datetime.Date raise {
  match rd.add_to_date(d) {
    Date(r) => r
    DateTime(r) => fail("expected a date, got \{r.repr()}")
  }
}

///|
/// `date - rd` expected to stay a date.
fn sub_d(d : @datetime.Date, rd : RelativeDelta) -> @datetime.Date raise {
  match rd.sub_from_date(d) {
    Date(r) => r
    DateTime(r) => fail("expected a date, got \{r.repr()}")
  }
}

///|
test "testMonthEndMonthBeginning" {
  assert_eq(
    RelativeDelta::between(dt(2003, 1, 31, h=23, mi=59, s=59), dt(2003, 3, 1)),
    RelativeDelta::new(months=-1, seconds=-1),
  )
  assert_eq(
    RelativeDelta::between(dt(2003, 3, 1), dt(2003, 1, 31, h=23, mi=59, s=59)),
    RelativeDelta::new(months=1, seconds=1),
  )
}

///|
test "testMonthEndMonthBeginningLeapYear" {
  assert_eq(
    RelativeDelta::between(dt(2012, 1, 31, h=23, mi=59, s=59), dt(2012, 3, 1)),
    RelativeDelta::new(months=-1, seconds=-1),
  )
  assert_eq(
    RelativeDelta::between(dt(2003, 3, 1), dt(2003, 1, 31, h=23, mi=59, s=59)),
    RelativeDelta::new(months=1, seconds=1),
  )
}

///|
test "testNextMonth" {
  assert_eq(
    RelativeDelta::new(months=1).add_to_datetime(now()),
    dt(2003, 10, 17, h=20, mi=54, s=47, us=282310),
  )
}

///|
test "testNextMonthPlusOneWeek" {
  assert_eq(
    RelativeDelta::new(months=1, weeks=1).add_to_datetime(now()),
    dt(2003, 10, 24, h=20, mi=54, s=47, us=282310),
  )
}

///|
test "testNextMonthPlusOneWeek10am" {
  assert_eq(
    RelativeDelta::new(months=1, weeks=1, hour=10).add_to_date(today()),
    DateTime(dt(2003, 10, 24, h=10)),
  )
}

///|
test "testNextMonthPlusOneWeek10amDiff" {
  assert_eq(
    RelativeDelta::between(dt(2003, 10, 24, h=10), today().to_datetime()),
    RelativeDelta::new(months=1, days=7, hours=10),
  )
}

///|
test "testOneMonthBeforeOneYear" {
  assert_eq(
    RelativeDelta::new(years=1, months=-1).add_to_datetime(now()),
    dt(2004, 8, 17, h=20, mi=54, s=47, us=282310),
  )
}

///|
test "testMonthsOfDiffNumOfDays" {
  assert_eq(
    add_d(date(2003, 1, 27), RelativeDelta::new(months=1)),
    date(2003, 2, 27),
  )
  assert_eq(
    add_d(date(2003, 1, 31), RelativeDelta::new(months=1)),
    date(2003, 2, 28),
  )
  assert_eq(
    add_d(date(2003, 1, 31), RelativeDelta::new(months=2)),
    date(2003, 3, 31),
  )
}

///|
test "testMonthsOfDiffNumOfDaysWithYears" {
  let plus1 = RelativeDelta::new(years=1)
  let minus1 = RelativeDelta::new(years=-1)
  assert_eq(add_d(date(2000, 2, 28), plus1), date(2001, 2, 28))
  assert_eq(add_d(date(2000, 2, 29), plus1), date(2001, 2, 28))
  assert_eq(add_d(date(1999, 2, 28), plus1), date(2000, 2, 28))
  assert_eq(add_d(date(1999, 3, 1), plus1), date(2000, 3, 1))
  assert_eq(add_d(date(1999, 3, 1), plus1), date(2000, 3, 1))
  assert_eq(add_d(date(2001, 2, 28), minus1), date(2000, 2, 28))
  assert_eq(add_d(date(2001, 3, 1), minus1), date(2000, 3, 1))
}

///|
test "testNextFriday" {
  assert_eq(add_d(today(), RelativeDelta::new(weekday=fr)), date(2003, 9, 19))
}

///|
test "testNextFridayInt" {
  // calendar.FRIDAY == 4
  assert_eq(
    add_d(today(), RelativeDelta::new(weekday=@datetime.Weekday::new(4))),
    date(2003, 9, 19),
  )
}

///|
test "testLastFridayInThisMonth" {
  assert_eq(
    add_d(today(), RelativeDelta::new(day=31, weekday=fr.nth(Some(-1)))),
    date(2003, 9, 26),
  )
}

///|
test "testLastDayOfFebruary" {
  assert_eq(
    add_d(date(2021, 2, 1), RelativeDelta::new(day=31)),
    date(2021, 2, 28),
  )
}

///|
test "testLastDayOfFebruaryLeapYear" {
  assert_eq(
    add_d(date(2020, 2, 1), RelativeDelta::new(day=31)),
    date(2020, 2, 29),
  )
}

///|
test "testNextWednesdayIsToday" {
  assert_eq(add_d(today(), RelativeDelta::new(weekday=we)), date(2003, 9, 17))
}

///|
test "testNextWednesdayNotToday" {
  assert_eq(
    add_d(today(), RelativeDelta::new(days=1, weekday=we)),
    date(2003, 9, 24),
  )
}

///|
test "testAddMoreThan12Months" {
  assert_eq(
    add_d(date(2003, 12, 1), RelativeDelta::new(months=13)),
    date(2005, 1, 1),
  )
}

///|
test "testAddNegativeMonths" {
  assert_eq(
    add_d(date(2003, 1, 1), RelativeDelta::new(months=-2)),
    date(2002, 11, 1),
  )
}

///|
test "test15thISOYearWeek" {
  assert_eq(
    add_d(
      date(2003, 1, 1),
      RelativeDelta::new(day=4, weeks=14, weekday=mo.nth(Some(-1))),
    ),
    date(2003, 4, 7),
  )
}

///|
test "testMillenniumAge" {
  assert_eq(
    RelativeDelta::between(now(), date(2001, 1, 1).to_datetime()),
    RelativeDelta::new(
      years=2,
      months=8,
      days=16,
      hours=20,
      minutes=54,
      seconds=47,
      microseconds=282310,
    ),
  )
}

///|
test "testJohnAge" {
  assert_eq(
    RelativeDelta::between(now(), dt(1978, 4, 5, h=12)),
    RelativeDelta::new(
      years=25,
      months=5,
      days=12,
      hours=8,
      minutes=54,
      seconds=47,
      microseconds=282310,
    ),
  )
}

///|
test "testJohnAgeWithDate" {
  assert_eq(
    RelativeDelta::between(today().to_datetime(), dt(1978, 4, 5, h=12)),
    RelativeDelta::new(years=25, months=5, days=11, hours=12),
  )
}

///|
test "testYearDay" {
  assert_eq(
    add_d(date(2003, 1, 1), RelativeDelta::new(yearday=260)),
    date(2003, 9, 17),
  )
  assert_eq(
    add_d(date(2002, 1, 1), RelativeDelta::new(yearday=260)),
    date(2002, 9, 17),
  )
  assert_eq(
    add_d(date(2000, 1, 1), RelativeDelta::new(yearday=260)),
    date(2000, 9, 16),
  )
  assert_eq(add_d(today(), RelativeDelta::new(yearday=261)), date(2003, 9, 18))
}

///|
test "testYearDayBug" {
  assert_eq(
    add_d(date(2010, 1, 1), RelativeDelta::new(yearday=15)),
    date(2010, 1, 15),
  )
}

///|
test "testNonLeapYearDay" {
  assert_eq(
    add_d(date(2003, 1, 1), RelativeDelta::new(nlyearday=260)),
    date(2003, 9, 17),
  )
  assert_eq(
    add_d(date(2002, 1, 1), RelativeDelta::new(nlyearday=260)),
    date(2002, 9, 17),
  )
  assert_eq(
    add_d(date(2000, 1, 1), RelativeDelta::new(nlyearday=260)),
    date(2000, 9, 17),
  )
  assert_eq(add_d(today(), RelativeDelta::new(yearday=261)), date(2003, 9, 18))
}

///|
test "testAddition" {
  assert_eq(
    RelativeDelta::new(days=10) +
    RelativeDelta::new(
      years=1,
      months=2,
      days=3,
      hours=4,
      minutes=5,
      microseconds=6,
    ),
    RelativeDelta::new(
      years=1,
      months=2,
      days=13,
      hours=4,
      minutes=5,
      microseconds=6,
    ),
  )
}

///|
test "testAbsoluteAddition" {
  assert_eq(
    RelativeDelta::new() + RelativeDelta::new(day=0, hour=0),
    RelativeDelta::new(day=0, hour=0),
  )
  assert_eq(
    RelativeDelta::new(day=0, hour=0) + RelativeDelta::new(),
    RelativeDelta::new(day=0, hour=0),
  )
}

///|
test "testAdditionToDatetime" {
  assert_eq(
    RelativeDelta::new(days=1).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 2),
  )
}

///|
test "testRightAdditionToDatetime" {
  // `rd + dt` and `dt + rd` are the same operation.
  assert_eq(
    RelativeDelta::new(days=1).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 2),
  )
}

///|
test "testAdditionFloatValue" {
  assert_eq(
    RelativeDelta::from_float(days=1.0).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 2),
  )
  assert_eq(
    RelativeDelta::from_float(months=1.0).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 2, 1),
  )
  assert_eq(
    RelativeDelta::from_float(years=1.0).add_to_datetime(dt(2000, 1, 1)),
    dt(2001, 1, 1),
  )
}

///|
test "testAdditionFloatFractionals" {
  assert_eq(
    RelativeDelta::from_float(days=0.5).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 1, h=12),
  )
  assert_eq(
    RelativeDelta::from_float(hours=0.5).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 1, mi=30),
  )
  assert_eq(
    RelativeDelta::from_float(minutes=0.5).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 1, s=30),
  )
  assert_eq(
    RelativeDelta::from_float(seconds=0.5).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 1, us=500000),
  )
  assert_eq(
    RelativeDelta::from_float(microseconds=500000.25).add_to_datetime(
      dt(2000, 1, 1),
    ),
    dt(2000, 1, 1, us=500000),
  )
}

///|
test "testSubtraction" {
  assert_eq(
    RelativeDelta::new(days=10) -
    RelativeDelta::new(
      years=1,
      months=2,
      days=3,
      hours=4,
      minutes=5,
      microseconds=6,
    ),
    RelativeDelta::new(
      years=-1,
      months=-2,
      days=7,
      hours=-4,
      minutes=-5,
      microseconds=-6,
    ),
  )
}

///|
test "testRightSubtractionFromDatetime" {
  assert_eq(
    RelativeDelta::new(days=1).sub_from_datetime(dt(2000, 1, 2)),
    dt(2000, 1, 1),
  )
}

///|
test "testMultiplication" {
  assert_eq(
    RelativeDelta::new(days=1).mul(28.0).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 29),
  )
}

///|
test "testDivision" {
  assert_eq(
    RelativeDelta::new(days=28).div(28.0).add_to_datetime(dt(2000, 1, 1)),
    dt(2000, 1, 2),
  )
}

///|
test "testBoolean" {
  assert_false(RelativeDelta::new(days=0).to_bool())
  assert_true(RelativeDelta::new(days=1).to_bool())
}

///|
test "testAbsoluteValueNegative" {
  let rd_base = RelativeDelta::new(
    years=-1,
    months=-5,
    days=-2,
    hours=-3,
    minutes=-5,
    seconds=-2,
    microseconds=-12,
  )
  let rd_expected = RelativeDelta::new(
    years=1,
    months=5,
    days=2,
    hours=3,
    minutes=5,
    seconds=2,
    microseconds=12,
  )
  assert_eq(rd_base.abs(), rd_expected)
}

///|
test "testAbsoluteValuePositive" {
  let rd_base = RelativeDelta::new(
    years=1,
    months=5,
    days=2,
    hours=3,
    minutes=5,
    seconds=2,
    microseconds=12,
  )
  assert_eq(rd_base.abs(), rd_base)
}

///|
test "testComparison" {
  let d1 = RelativeDelta::new(
    years=1,
    months=1,
    days=1,
    leapdays=0,
    hours=1,
    minutes=1,
    seconds=1,
    microseconds=1,
  )
  let d2 = RelativeDelta::new(
    years=1,
    months=1,
    days=1,
    leapdays=0,
    hours=1,
    minutes=1,
    seconds=1,
    microseconds=1,
  )
  let d3 = RelativeDelta::new(
    years=1,
    months=1,
    days=1,
    leapdays=0,
    hours=1,
    minutes=1,
    seconds=1,
    microseconds=2,
  )
  assert_eq(d1, d2)
  assert_not_eq(d1, d3)
}

///|
test "testInequalityWeekdays" {
  let no_wday = RelativeDelta::new(year=1997, month=4)
  let wday_mo_1 = RelativeDelta::new(
    year=1997,
    month=4,
    weekday=mo.nth(Some(1)),
  )
  let wday_mo_2 = RelativeDelta::new(
    year=1997,
    month=4,
    weekday=mo.nth(Some(2)),
  )
  let wday_tu = RelativeDelta::new(year=1997, month=4, weekday=tu)
  assert_true(wday_mo_1 == wday_mo_1)
  assert_false(no_wday == wday_mo_1)
  assert_false(wday_mo_1 == no_wday)
  assert_false(wday_mo_1 == wday_mo_2)
  assert_false(wday_mo_2 == wday_mo_1)
  assert_false(wday_mo_1 == wday_tu)
  assert_false(wday_tu == wday_mo_1)
}

///|
test "testMonthOverflow" {
  assert_eq(
    RelativeDelta::new(months=273),
    RelativeDelta::new(years=22, months=9),
  )
}

///|
test "testWeeks" {
  let rd = RelativeDelta::new(years=4, months=2, weeks=8, days=6)
  assert_eq((rd.weeks(), rd.days), (8, (8 * 7 + 6).to_double()))
  rd.set_weeks(3)
  assert_eq((rd.weeks(), rd.days), (3, (3 * 7 + 6).to_double()))
}

///|
test "testRelativeDeltaRepr" {
  inspect(
    RelativeDelta::new(years=1, months=-1, days=15).repr(),
    content="relativedelta(years=+1, months=-1, days=+15)",
  )
  inspect(
    RelativeDelta::new(months=14, seconds=-25).repr(),
    content="relativedelta(years=+1, months=+2, seconds=-25)",
  )
  inspect(
    RelativeDelta::new(month=3, hour=3, weekday=su.nth(Some(3))).repr(),
    content="relativedelta(month=3, weekday=SU(+3), hour=3)",
  )
}

///|
test "testRelativeDeltaFractionalYear" {
  try RelativeDelta::from_float(years=1.5) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected error \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "testRelativeDeltaFractionalMonth" {
  try RelativeDelta::from_float(months=1.5) catch {
    @datetime.ValueError(_) => ()
    e => fail("unexpected error \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "testRelativeDeltaFractionalRepr" {
  inspect(
    RelativeDelta::from_float(years=3.0, months=-2.0, days=1.25).repr(),
    content="relativedelta(years=+3, months=-2, days=+1.25)",
  )
  inspect(
    RelativeDelta::from_float(hours=0.5, seconds=9.22).repr(),
    content="relativedelta(hours=+0.5, seconds=+9.22)",
  )
}

///|
test "testRelativeDeltaFractionalWeeks" {
  // Equivalent to days=8, hours=18
  let rd = RelativeDelta::from_float(weeks=1.25)
  assert_eq(rd.add_to_datetime(dt(2009, 9, 3)), dt(2009, 9, 11, h=18))
}

///|
test "testRelativeDeltaFractionalDays" {
  let d1 = dt(2009, 9, 3)
  assert_eq(
    RelativeDelta::from_float(days=1.48).add_to_datetime(d1),
    dt(2009, 9, 4, h=11, mi=31, s=12),
  )
  assert_eq(
    RelativeDelta::from_float(days=1.5).add_to_datetime(d1),
    dt(2009, 9, 4, h=12),
  )
}

///|
test "testRelativeDeltaFractionalHours" {
  let rd = RelativeDelta::from_float(days=1.0, hours=12.5)
  assert_eq(rd.add_to_datetime(dt(2009, 9, 3)), dt(2009, 9, 4, h=12, mi=30))
}

///|
test "testRelativeDeltaFractionalMinutes" {
  let rd = RelativeDelta::from_float(hours=1.0, minutes=30.5)
  assert_eq(
    rd.add_to_datetime(dt(2009, 9, 3)),
    dt(2009, 9, 3, h=1, mi=30, s=30),
  )
}

///|
test "testRelativeDeltaFractionalSeconds" {
  let rd = RelativeDelta::from_float(hours=5.0, minutes=30.0, seconds=30.5)
  assert_eq(
    rd.add_to_datetime(dt(2009, 9, 3)),
    dt(2009, 9, 3, h=5, mi=30, s=30, us=500000),
  )
}

///|
test "testRelativeDeltaFractionalPositiveOverflow" {
  let d1 = dt(2009, 9, 3)
  // Equivalent to (days=1, hours=14)
  let rd1 = RelativeDelta::from_float(days=1.5, hours=2.0)
  assert_eq(rd1.add_to_datetime(d1), dt(2009, 9, 4, h=14))
  // Equivalent to (days=1, hours=14, minutes=45)
  let rd2 = RelativeDelta::from_float(days=1.5, hours=2.5, minutes=15.0)
  assert_eq(rd2.add_to_datetime(d1), dt(2009, 9, 4, h=14, mi=45))
  // Carry back up - equivalent to (days=2, hours=2, minutes=0, seconds=1)
  let rd3 = RelativeDelta::from_float(
    days=1.5,
    hours=13.0,
    minutes=59.5,
    seconds=31.0,
  )
  assert_eq(rd3.add_to_datetime(d1), dt(2009, 9, 5, h=2, s=1))
}

///|
test "testRelativeDeltaFractionalNegativeDays" {
  let d1 = dt(2009, 9, 3, h=12)
  // Equivalent to (days=-1, hours=-1)
  let rd1 = RelativeDelta::from_float(days=-1.5, hours=11.0)
  assert_eq(rd1.add_to_datetime(d1), dt(2009, 9, 2, h=11))
  // Equivalent to (days=-1, hours=-9)
  let rd2 = RelativeDelta::from_float(days=-1.25, hours=-3.0)
  assert_eq(rd2.add_to_datetime(d1), dt(2009, 9, 2, h=3))
}

///|
test "testRelativeDeltaNormalizeFractionalDays" {
  // Equivalent to (days=2, hours=18)
  assert_eq(
    RelativeDelta::from_float(days=2.75).normalized(),
    RelativeDelta::new(days=2, hours=18),
  )
  // Equivalent to (days=1, hours=11, minutes=31, seconds=12)
  assert_eq(
    RelativeDelta::from_float(days=1.48).normalized(),
    RelativeDelta::new(days=1, hours=11, minutes=31, seconds=12),
  )
}

///|
test "testRelativeDeltaNormalizeFractionalDays2" {
  // Equivalent to (hours=1, minutes=30)
  assert_eq(
    RelativeDelta::from_float(hours=1.5).normalized(),
    RelativeDelta::new(hours=1, minutes=30),
  )
  // Equivalent to (hours=3, minutes=17, seconds=5, microseconds=100)
  assert_eq(
    RelativeDelta::from_float(hours=3.28472225).normalized(),
    RelativeDelta::new(hours=3, minutes=17, seconds=5, microseconds=100),
  )
}

///|
test "testRelativeDeltaNormalizeFractionalMinutes" {
  // Equivalent to (minutes=15, seconds=36)
  assert_eq(
    RelativeDelta::from_float(minutes=15.6).normalized(),
    RelativeDelta::new(minutes=15, seconds=36),
  )
  // Equivalent to (minutes=25, seconds=20, microseconds=25000)
  assert_eq(
    RelativeDelta::from_float(minutes=25.33375).normalized(),
    RelativeDelta::new(minutes=25, seconds=20, microseconds=25000),
  )
}

///|
test "testRelativeDeltaNormalizeFractionalSeconds" {
  // Equivalent to (seconds=45, microseconds=25000)
  assert_eq(
    RelativeDelta::from_float(seconds=45.025).normalized(),
    RelativeDelta::new(seconds=45, microseconds=25000),
  )
}

///|
test "testRelativeDeltaFractionalPositiveOverflow2" {
  // Equivalent to (days=1, hours=14)
  assert_eq(
    RelativeDelta::from_float(days=1.5, hours=2.0).normalized(),
    RelativeDelta::new(days=1, hours=14),
  )
  // Equivalent to (days=1, hours=14, minutes=45)
  assert_eq(
    RelativeDelta::from_float(days=1.5, hours=2.5, minutes=15.0).normalized(),
    RelativeDelta::new(days=1, hours=14, minutes=45),
  )
  // Carry back up - equivalent to:
  // (days=2, hours=2, minutes=0, seconds=2, microseconds=3)
  let rd3 = RelativeDelta::from_float(
    days=1.5,
    hours=13.0,
    minutes=59.50045,
    seconds=31.473,
    microseconds=500003.0,
  )
  assert_eq(
    rd3.normalized(),
    RelativeDelta::new(days=2, hours=2, minutes=0, seconds=2, microseconds=3),
  )
}

///|
test "testRelativeDeltaFractionalNegativeOverflow" {
  // Equivalent to (days=-1)
  assert_eq(
    RelativeDelta::from_float(days=-0.5, hours=-12.0).normalized(),
    RelativeDelta::new(days=-1),
  )
  // Equivalent to (days=-1)
  assert_eq(
    RelativeDelta::from_float(days=-1.5, hours=12.0).normalized(),
    RelativeDelta::new(days=-1),
  )
  // Equivalent to (days=-1, hours=-14, minutes=-45)
  assert_eq(
    RelativeDelta::from_float(days=-1.5, hours=-2.5, minutes=-15.0).normalized(),
    RelativeDelta::new(days=-1, hours=-14, minutes=-45),
  )
  // Equivalent to (days=-1, hours=-14, minutes=+15)
  assert_eq(
    RelativeDelta::from_float(days=-1.5, hours=-2.5, minutes=45.0).normalized(),
    RelativeDelta::new(days=-1, hours=-14, minutes=15),
  )
  // Carry back up - equivalent to:
  // (days=-2, hours=-2, minutes=0, seconds=-2, microseconds=-3)
  let rd3 = RelativeDelta::from_float(
    days=-1.5,
    hours=-13.0,
    minutes=-59.50045,
    seconds=-31.473,
    microseconds=-500003.0,
  )
  assert_eq(
    rd3.normalized(),
    RelativeDelta::new(
      days=-2,
      hours=-2,
      minutes=0,
      seconds=-2,
      microseconds=-3,
    ),
  )
}

///|
test "testInvalidYearDay" {
  try RelativeDelta::new(yearday=367) catch {
    @datetime.ValueError(msg) => inspect(msg, content="invalid year day (367)")
    e => fail("unexpected error \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "testAddTimedeltaToUnpopulatedRelativedelta" {
  let td = @datetime.TimeDelta::new(
    days=1,
    seconds=1,
    microseconds=1,
    milliseconds=1,
    minutes=1,
    hours=1,
    weeks=1,
  )
  let expected = RelativeDelta::new(
    weeks=1,
    days=1,
    hours=1,
    minutes=1,
    seconds=1,
    microseconds=1001,
  )
  assert_eq(expected, RelativeDelta::new().add_timedelta(td))
}

///|
test "testAddTimedeltaToPopulatedRelativeDelta" {
  let td = @datetime.TimeDelta::new(
    days=1,
    seconds=1,
    microseconds=1,
    milliseconds=1,
    minutes=1,
    hours=1,
    weeks=1,
  )
  let rd = RelativeDelta::new(
    year=1,
    month=1,
    day=1,
    hour=1,
    minute=1,
    second=1,
    microsecond=1,
    years=1,
    months=1,
    days=1,
    weeks=1,
    hours=1,
    minutes=1,
    seconds=1,
    microseconds=1,
  )
  let expected = RelativeDelta::new(
    year=1,
    month=1,
    day=1,
    hour=1,
    minute=1,
    second=1,
    microsecond=1,
    years=1,
    months=1,
    weeks=2,
    days=2,
    hours=2,
    minutes=2,
    seconds=2,
    microseconds=1002,
  )
  assert_eq(expected, rd.add_timedelta(td))
}

///|
test "testHashable" {
  let m : Map[RelativeDelta, String] = Map([])
  m[RelativeDelta::new(minute=1)] = "test"
  assert_eq(m.get(RelativeDelta::new(minute=1)), Some("test"))
}

///|
test "testDayOfMonthPlus" {
  let rd = RelativeDelta::new(months=1)
  assert_eq(
    [
      add_d(date(2021, 1, 28), rd),
      add_d(date(2021, 2, 27), rd),
      add_d(date(2021, 4, 29), rd),
      add_d(date(2021, 5, 30), rd),
    ],
    [date(2021, 2, 28), date(2021, 3, 27), date(2021, 5, 29), date(2021, 6, 30)],
  )
}

///|
test "testLastDayOfMonthPlus" {
  let rd = RelativeDelta::new(months=1)
  assert_eq(
    [
      add_d(date(2021, 1, 31), rd),
      add_d(date(2021, 1, 30), rd),
      add_d(date(2021, 1, 29), rd),
      add_d(date(2021, 1, 28), rd),
      add_d(date(2021, 2, 28), rd),
      add_d(date(2021, 4, 30), rd),
      add_d(date(2021, 5, 31), rd),
    ],
    [
      date(2021, 2, 28),
      date(2021, 2, 28),
      date(2021, 2, 28),
      date(2021, 2, 28),
      date(2021, 3, 28),
      date(2021, 5, 30),
      date(2021, 6, 30),
    ],
  )
}

///|
test "testDayOfMonthMinus" {
  let rd = RelativeDelta::new(months=1)
  assert_eq(
    [
      sub_d(date(2021, 2, 27), rd),
      sub_d(date(2021, 3, 30), rd),
      sub_d(date(2021, 3, 29), rd),
      sub_d(date(2021, 3, 28), rd),
      sub_d(date(2021, 5, 30), rd),
      sub_d(date(2021, 6, 29), rd),
    ],
    [
      date(2021, 1, 27),
      date(2021, 2, 28),
      date(2021, 2, 28),
      date(2021, 2, 28),
      date(2021, 4, 30),
      date(2021, 5, 29),
    ],
  )
}

///|
test "testLastDayOfMonthMinus" {
  let rd = RelativeDelta::new(months=1)
  assert_eq(
    [
      sub_d(date(2021, 2, 28), rd),
      sub_d(date(2021, 3, 31), rd),
      sub_d(date(2021, 5, 31), rd),
      sub_d(date(2021, 6, 30), rd),
    ],
    [date(2021, 1, 28), date(2021, 2, 28), date(2021, 4, 30), date(2021, 5, 30)],
  )
}

// RelativeDeltaWeeksPropertyGetterTest

///|
test "RelativeDeltaWeeksPropertyGetterTest.test_one_day" {
  let rd = RelativeDelta::new(days=1)
  assert_eq(rd.days, 1.0)
  assert_eq(rd.weeks(), 0)
}

///|
test "RelativeDeltaWeeksPropertyGetterTest.test_minus_one_day" {
  let rd = RelativeDelta::new(days=-1)
  assert_eq(rd.days, -1.0)
  assert_eq(rd.weeks(), 0)
}

///|
test "RelativeDeltaWeeksPropertyGetterTest.test_height_days" {
  let rd = RelativeDelta::new(days=8)
  assert_eq(rd.days, 8.0)
  assert_eq(rd.weeks(), 1)
}

///|
test "RelativeDeltaWeeksPropertyGetterTest.test_minus_height_days" {
  let rd = RelativeDelta::new(days=-8)
  assert_eq(rd.days, -8.0)
  assert_eq(rd.weeks(), -1)
}

// RelativeDeltaWeeksPropertySetterTest

///|
test "RelativeDeltaWeeksPropertySetterTest.test_one_day_set_one_week" {
  let rd = RelativeDelta::new(days=1)
  rd.set_weeks(1) // add 7 days
  assert_eq(rd.days, 8.0)
  assert_eq(rd.weeks(), 1)
}

///|
test "RelativeDeltaWeeksPropertySetterTest.test_minus_one_day_set_one_week" {
  let rd = RelativeDelta::new(days=-1)
  rd.set_weeks(1) // add 7 days
  assert_eq(rd.days, 6.0)
  assert_eq(rd.weeks(), 0)
}

///|
test "RelativeDeltaWeeksPropertySetterTest.test_height_days_set_minus_one_week" {
  let rd = RelativeDelta::new(days=8)
  rd.set_weeks(-1) // change from 1 week, 1 day to -1 week, 1 day
  assert_eq(rd.days, -6.0)
  assert_eq(rd.weeks(), 0)
}

///|
test "RelativeDeltaWeeksPropertySetterTest.test_minus_height_days_set_minus_one_week" {
  let rd = RelativeDelta::new(days=-8)
  rd.set_weeks(-1) // does not change anything
  assert_eq(rd.days, -8.0)
  assert_eq(rd.weeks(), -1)
}
