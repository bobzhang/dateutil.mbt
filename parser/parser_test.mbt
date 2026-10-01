// Hand-ported tests from dateutil tests/test_parser.py that the generator
// (tools/gen_parser_upstream_tests.py) cannot express: custom parserinfo
// subclasses, zone objects / callables in `tzinfos`, byte inputs and
// ParserError's repr.

///|
fn same_tz(a : @datetime.DateTime, b : @datetime.DateTime) -> Bool {
  match (a.tzinfo, b.tzinfo) {
    (None, None) => true
    (Some(x), Some(y)) => x.is_same(y)
    _ => false
  }
}

///|
test "test_parser::TestInputTypes::test_parse_bytes (adapted: decode first)" {
  let res = @parser.parse(@utf8.decode(b"2014 January 19"))
  assert_eq(res, dt(2014, 1, 19))
}

///|
test "test_parser::TestInputTypes::test_parse_str (adapted: decode first)" {
  let uni_str = "2014-05-01 08:00:00"
  let bytes_str = @utf8.encode(uni_str)
  assert_eq(@parser.parse(@utf8.decode(bytes_str)), @parser.parse(uni_str))
}

///|
test "test_parser::ParserTest::testParserParseStr (adapted: decode first)" {
  let uni_str = "2014-05-01 08:00:00"
  let p = @parser.Parser::new()
  assert_eq(p.parse(@utf8.decode(@utf8.encode(uni_str))), p.parse(uni_str))
}

///|
test "test_parser::TestTzinfoInputTypes::test_tzinfo_dict_could_return_none" {
  let result = @parser.parse(
    "2017-02-03 12:40 BRST",
    tzinfos=Table({ "BRST": NoTz }),
  )
  let expected = dt(2017, 2, 3, hour=12, minute=40)
  assert_eq(result, expected)
  assert_true(same_tz(result, expected))
}

///|
test "test_parser::TestTzinfoInputTypes::test_tzinfos_callable_could_return_none" {
  let result = @parser.parse(
    "2017-02-03 12:40 BRST",
    tzinfos=Callback((_, _) => NoTz),
  )
  let expected = dt(2017, 2, 3, hour=12, minute=40)
  assert_eq(result, expected)
  assert_true(same_tz(result, expected))
}

///|
test "test_parser::TestTzinfoInputTypes::test_valid_tzinfo_tzinfo_input" {
  let tzinfos = @parser.Table({ "UTC": Zone(@tz.utc) })
  let res = @parser.parse("2014 January 19 09:00 UTC", tzinfos~)
  let expected = dt(2014, 1, 19, hour=9).with_tzinfo(Some(@tz.utc))
  assert_eq(res, expected)
  assert_true(same_tz(res, expected))
}

///|
test "test_parser::TestTzinfoInputTypes::test_valid_tzinfo_int_input" {
  let tzinfos = @parser.Table({ "UTC": Offset(-28800) })
  let res = @parser.parse("2014 January 19 09:00 UTC", tzinfos~)
  let expected = dt(2014, 1, 19, hour=9).with_tzinfo(
    Some(@tz.tzoffset(Some("UTC"), -28800)),
  )
  assert_eq(res, expected)
  assert_true(same_tz(res, expected))
}

///|
test "tzinfos callback receives (tzname, tzoffset)" {
  let seen = []
  let tzinfos = @parser.Callback((name, off) => {
    seen.push((name, off))
    Offset(3600)
  })
  let res = @parser.parse("2014-01-19 09:00 BRST", tzinfos~)
  inspect(
    res.repr(),
    content="datetime.datetime(2014, 1, 19, 9, 0, tzinfo=tzoffset('BRST', 3600))",
  )
  // Like Python, a callable is consulted even without a zone in the string.
  let res = @parser.parse("2014-01-19 09:00", tzinfos~)
  inspect(
    res.repr(),
    content="datetime.datetime(2014, 1, 19, 9, 0, tzinfo=tzoffset(None, 3600))",
  )
  let res = @parser.parse("2014-01-19 09:00 -0300", tzinfos~)
  inspect(
    res.repr(),
    content="datetime.datetime(2014, 1, 19, 9, 0, tzinfo=tzoffset(None, 3600))",
  )
  debug_inspect(
    seen,
    content=(
      #|[(Some("BRST"), None), (None, None), (None, Some(-10800))]
    ),
  )
}

///|
test "test_parser::ParserTest::testParseUnicodeWords" {
  let rus_parserinfo = @parser.ParserInfo::new(months=[
    ["янв", "Январь"],
    ["фев", "Февраль"],
    ["мар", "Март"],
    ["апр", "Апрель"],
    ["май", "Май"],
    ["июн", "Июнь"],
    ["июл", "Июль"],
    ["авг", "Август"],
    ["сен", "Сентябрь"],
    ["окт", "Октябрь"],
    ["ноя", "Ноябрь"],
    ["дек", "Декабрь"],
  ])
  let expected = dt(2015, 9, 10, hour=10, minute=20)
  let res = @parser.parse(
    "10 Сентябрь 2015 10:20",
    parserinfo=rus_parserinfo,
  )
  assert_eq(res, expected)
  // Python lower-cases Unicode words, so other casings match too.
  let res = @parser.parse(
    "10 СЕНТЯБРЬ 2015 10:20",
    parserinfo=rus_parserinfo,
  )
  assert_eq(res, expected)
}

///|
test "test_parser::ParserTest::testCustomParserInfo" {
  let months = @parser.default_months.copy()
  months[0] = ["Foo", "Foo"]
  let myparser = @parser.Parser::new(info=@parser.ParserInfo::new(months~))
  let d = myparser.parse("01/Foo/2007")
  assert_eq(d, dt(2007, 1, 1))
}

///|
test "test_parser::ParserTest::testCustomParserShortDaynames" {
  let german = @parser.ParserInfo::new(weekdays=[
    ["Mo", "Montag"],
    ["Di", "Dienstag"],
    ["Mi", "Mittwoch"],
    ["Do", "Donnerstag"],
    ["Fr", "Freitag"],
    ["Sa", "Samstag"],
    ["So", "Sonntag"],
  ])
  let myparser = @parser.Parser::new(info=german)
  let d = myparser.parse("Sa 21. Jan 2017")
  assert_eq(d, dt(2017, 1, 21))
}

///|
test "parserinfo convertyear hook (Python: overriding convertyear)" {
  // Always map two-digit years into the 1900s.
  let info = @parser.ParserInfo::new(convertyear=(info, year, century) => {
    if year < 100 && !century {
      1900 + year
    } else {
      info.default_convertyear(year, century_specified=century)
    }
  })
  assert_eq(@parser.parse("10/09/03", parserinfo=info), dt(1903, 10, 9))
  assert_eq(@parser.parse("10/09/2003", parserinfo=info), dt(2003, 10, 9))
}

///|
test "parserinfo tables: jump, tzoffset, dayfirst defaults" {
  let info = @parser.ParserInfo::new(
    dayfirst=true,
    tzoffset={ "BRST": -10800 },
    jump=[..@parser.default_jump, "um"],
  )
  let p = @parser.Parser::new(info~)
  assert_eq(p.parse("10.09.2003 um 10:00"), dt(2003, 9, 10, hour=10))
  inspect(
    p.parse("10.09.2003 10:00 BRST").repr(),
    content="datetime.datetime(2003, 9, 10, 10, 0, tzinfo=tzoffset('BRST', -10800))",
  )
  // explicit arguments win over the parserinfo defaults
  assert_eq(p.parse("10.09.2003", dayfirst=false), dt(2003, 10, 9))
}

///|
test "parserinfo reference year for two-digit years" {
  let info = @parser.ParserInfo::new(year=2026)
  inspect(info.convertyear(75), content="2075")
  inspect(info.convertyear(76), content="1976")
  inspect(info.convertyear(77, century_specified=true), content="77")
  let info = @parser.ParserInfo::new(year=1990)
  inspect(
    info.convertyear(40),
    content=(
      #|1940
    ),
  )
  inspect(info.convertyear(41), content="1941")
}

///|
test "test_parser::test_parsererror_repr" {
  let e = @parser.ParserError("Problem with string: %s", "2019-01-01")
  assert_eq(e.repr(), "ParserError('Problem with string: %s', '2019-01-01')")
}

///|
test "test_parser::ParserTest::test_includes_timestr" {
  let timestr = "2020-13-97T44:61:83"
  try @parser.parse(timestr) catch {
    @parser.ParserError(_, arg) => assert_eq(arg, timestr)
    e => fail("unexpected error \{e}")
  } noraise {
    _ => fail("Failed to raise ParserError")
  }
}

///|
test "test_parser::ParserTest::testFuzzyIgnoreAMPM (UnknownTimezoneWarning)" {
  let warnings = []
  let res = @parser.parse(
    "Jan 29, 1945 14:45 AM I going to see you there?",
    fuzzy=true,
    on_warning=w => warnings.push(w),
  )
  assert_eq(res, dt(1945, 1, 29, hour=14, minute=45))
  debug_inspect(warnings, content="[{ tzname: \"I\" }]")
  inspect(
    warnings[0],
    content="tzname I identified but not understood.  Pass `tzinfos` argument in order to correctly return a timezone-aware datetime.  In a future version, this will raise an exception.",
  )
}

///|
test "timelex_split" {
  debug_inspect(
    @parser.timelex_split("Today is 25 of September of 2003, exactly"),
    content=(
      #|[
      #|  "Today",
      #|  " ",
      #|  "is",
      #|  " ",
      #|  "25",
      #|  " ",
      #|  "of",
      #|  " ",
      #|  "September",
      #|  " ",
      #|  "of",
      #|  " ",
      #|  "2003",
      #|  ",",
      #|  " ",
      #|  "exactly",
      #|]
    ),
  )
  debug_inspect(
    @parser.timelex_split("\u{0}\u{0}August 29, 1924 10,5 1.a 4.Sep"),
    content=(
      #|[
      #|  "August",
      #|  " ",
      #|  "29",
      #|  ",",
      #|  " ",
      #|  "1924",
      #|  " ",
      #|  "10.5",
      #|  " ",
      #|  "1",
      #|  ".",
      #|  "a",
      #|  " ",
      #|  "4",
      #|  ".",
      #|  "Sep",
      #|]
    ),
  )
}
