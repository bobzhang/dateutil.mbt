// Port of upstream tests/test_tz.py `TZICalTest` (and the tzical cases
// of `TZTest`).

///|
fn ical_zone(name : String) -> @datetime.Tz raise {
  @tzical.TzIcal::from_string(ical_str(name)).get().unwrap()
}

///|
/// `_tzstr_dtstart_with_params`: add parameters to every DTSTART line.
fn ical_str_dtstart_with_params(name : String, param_str : String) -> String {
  ical_str(name)
  .split("\n")
  .map(line => {
    let line = line.to_owned()
    if line.has_prefix("DTSTART") {
      let i = line.find(":").unwrap()
      line.view(end_offset=i).to_owned() +
      ";" +
      param_str +
      ":" +
      line.view(start_offset=i + 1).to_owned()
    } else {
      line
    }
  })
  .collect()
  .join("\n")
}

///|
test "TZICalTest: TzFoldMixin" {
  fold_mixin(name => ical_zone(name))
}

///|
test "TZICalTest: testRepr" {
  let tzc = @tzical.TzIcal::from_string(
    tzical_pst8pdt,
    name="StringIO(PST8PDT)",
  )
  inspect(tzc.repr(), content="tzical('StringIO(PST8PDT)')")
  inspect(tzc.get().unwrap(), content="<tzicalvtz 'US-Pacific'>")
}

///|
/// `_test_us_zone`: (start of DST, end of DST) probes with folds.
fn us_zone_probes(
  tzc : @datetime.Tz,
  start : Bool,
) -> Array[@datetime.DateTime] {
  if start {
    [
      dt(2003, 3, 9, hour=1, minute=59, tz=tzc),
      dt(2003, 3, 9, hour=2, minute=0, tz=tzc),
    ]
  } else {
    [
      dt(2003, 11, 2, hour=0, minute=59, tz=tzc),
      dt(2003, 11, 2, hour=1, minute=0, tz=tzc, fold=1),
    ]
  }
}

///|
fn check_us_zone(
  tzc : @datetime.Tz,
  start : Bool,
  std : (String, Int),
  dst : (String, Int),
) -> Unit raise {
  // values in (start of DST) order: std then dst; reversed at the end of DST
  let values = if start { [std, dst] } else { [dst, std] }
  let probes = us_zone_probes(tzc, start)
  for i, d in probes {
    let (name, off) = values[i]
    let is_dst = name == dst.0
    // name
    assert_eq(d.tzname(), Some(name))
    // offset
    assert_eq(d.utcoffset(), Some(hours(off)))
    // dst
    assert_eq(d.dst(), Some(hours(if is_dst { 1 } else { 0 })))
  }
}

///|
test "TZICalTest: testEST{Start,End}{Name,Offset,DST}" {
  let tzc = ical_zone("America/New_York")
  check_us_zone(tzc, true, ("EST", -5), ("EDT", -4))
  check_us_zone(tzc, false, ("EST", -5), ("EDT", -4))
}

///|
test "TZICalTest: testESTValueDatetime" {
  let s = ical_str_dtstart_with_params("America/New_York", "VALUE=DATE-TIME")
  let tzc = @tzical.TzIcal::from_string(s).get().unwrap()
  check_us_zone(tzc, true, ("EST", -5), ("EDT", -4))
  check_us_zone(tzc, false, ("EST", -5), ("EDT", -4))
}

///|
test "TZICalTest: testMultiZone{Start,End}{Name,Offset,DST}" {
  let tzic = @tzical.TzIcal::from_string(
    ical_str("America/New_York") + "\n" + ical_str("America/Los_Angeles"),
  )
  let est = tzic.get(tzid="US-Eastern").unwrap()
  let pst = tzic.get(tzid="US-Pacific").unwrap()
  for start in [true, false] {
    check_us_zone(est, start, ("EST", -5), ("EDT", -4))
    check_us_zone(pst, start, ("PST", -8), ("PDT", -7))
  }
}

///|
test "TZICalTest: testMultiZoneKeys / testGap" {
  let tzic = @tzical.TzIcal::from_string(
    ical_str("America/New_York") + "\n" + ical_str("America/Los_Angeles"),
  )
  let keys = tzic.keys()
  keys.sort()
  debug_inspect(keys, content="[\"US-Eastern\", \"US-Pacific\"]")
  let tzic = @tzical.TzIcal::from_string(tzical_est5edt + "\n" + tzical_pst8pdt)
  let keys = tzic.keys()
  keys.sort()
  debug_inspect(keys, content="[\"US-Eastern\", \"US-Pacific\"]")
  assert_true(tzic.get(tzid="Nowhere") is None)
}

///|
fn expect_value_error(f : () -> Unit raise, msg : String) -> Unit raise {
  try f() catch {
    @datetime.ValueError(m) => assert_eq(m, msg)
    e => fail("expected ValueError, got \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "TZICalTest: error conditions" {
  // testEmptyString
  expect_value_error(
    () => @tzical.TzIcal::from_string("") |> ignore,
    "empty string",
  )
  // testMultiZoneGet
  let tzic = @tzical.TzIcal::from_string(tzical_est5edt + tzical_pst8pdt)
  expect_value_error(
    () => tzic.get() |> ignore,
    "more than one timezone available",
  )
  // testDtstartDate
  expect_value_error(
    () => {
      @tzical.TzIcal::from_string(
        ical_str_dtstart_with_params("America/New_York", "VALUE=DATE"),
      )
      |> ignore
    },
    "Unsupported DTSTART param in VTIMEZONE: VALUE=DATE",
  )
  // testDtstartTzid
  expect_value_error(
    () => {
      @tzical.TzIcal::from_string(
        ical_str_dtstart_with_params("America/New_York", "TZID=UTC"),
      )
      |> ignore
    },
    "Unsupported DTSTART param in VTIMEZONE: TZID=UTC",
  )
  // testDtstartBadParam
  expect_value_error(
    () => {
      @tzical.TzIcal::from_string(
        ical_str_dtstart_with_params("America/New_York", "FOO=BAR"),
      )
      |> ignore
    },
    "Unsupported DTSTART param in VTIMEZONE: FOO=BAR",
  )
  // no zones at all
  let empty = @tzical.TzIcal::from_string("BEGIN:VCALENDAR\nEND:VCALENDAR")
  expect_value_error(() => empty.get() |> ignore, "no timezones defined")
}

///|
test "tzical: more parse errors (messages match dateutil)" {
  let cases : Array[(String, String)] = [
    ("BEGIN:VTIMEZONE\nBEGIN:FOO", "unknown component: FOO"),
    (
      "BEGIN:VTIMEZONE\nTZID:X\nEND:VTIMEZONE", "at least one component is needed",
    ),
    ("BEGIN:VTIMEZONE\nEND:VTIMEZONE", "mandatory TZID not found"),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nEND:VTIMEZONE", "component not closed: STANDARD",
    ),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nEND:STANDARD", "mandatory DTSTART not found",
    ),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nDTSTART:19700101T000000\nEND:STANDARD", "mandatory TZOFFSETFROM not found",
    ),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nTZOFFSETFROM:+01\nEND:STANDARD", "invalid offset: 01",
    ),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nTZOFFSETFROM: \nEND:STANDARD", "empty offset",
    ),
    ("BEGIN:VTIMEZONE\nFOO:BAR", "unsupported property: FOO"),
    ("BEGIN:VTIMEZONE\nTZID;X=Y:Z", "unsupported TZID parm: X=Y"),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nTZNAME;LANGUAGE=en:EST", "unsupported TZNAME parm: LANGUAGE=en",
    ),
    (
      "BEGIN:VTIMEZONE\nBEGIN:STANDARD\nEND:DAYLIGHT", "invalid component end: DAYLIGHT",
    ),
    (
      "BEGIN:VTIMEZONE\nNOCOLON", "not enough values to unpack (expected 2, got 1)",
    ),
  ]
  for case in cases {
    let (s, msg) = case
    expect_value_error(() => @tzical.TzIcal::from_string(s) |> ignore, msg)
  }
}

///|
test "tzical: single component zone and folded lines" {
  let s =
    #|BEGIN:VTIMEZONE
    #|TZID:Fixed
    #|BEGIN:STANDARD
    #|DTSTART:19700101T000000
    #|TZOFFSETFROM:+0530
    #|TZOFFSETTO:+0530
    #|TZNA
    #| ME:IST
    #|END:STANDARD
    #|END:VTIMEZONE
  // A continuation line starts with a space; "TZNA" + "ME:IST" unfolds.
  let tzc = @tzical.TzIcal::from_string(s).get().unwrap()
  let d = dt(2020, 1, 1, tz=tzc)
  inspect(d, content="2020-01-01 00:00:00+05:30")
  assert_eq(d.tzname(), Some("IST"))
  // single-component zones answer `Time` (None datetime) queries too
  let t = @datetime.Time::new(hour=1, tzinfo=tzc)
  inspect(t, content="01:00:00")
  inspect(t.strftime("%H%M%Z"), content="0100IST")
}

///|
test "tzical: Show/to_string is repr" {
  let tzc = @tzical.TzIcal::from_string(tzical_pst8pdt, name="f.ics")
  inspect(tzc.to_string(), content="tzical('f.ics')")
  inspect("\{tzc}", content="tzical('f.ics')")
}

///|
test "tzical: a component rrule that raises counts as no onset" {
  // BYEASTER=400 indexes past the easter mask: Python's first utcoffset()
  // raises IndexError from inside _find_comp (later queries then hang in
  // the broken rrule cache). TzInfo queries cannot raise here, so the
  // failing component is skipped like one without an onset before `dt`.
  let s =
    #|BEGIN:VTIMEZONE
    #|TZID:Bad-Easter
    #|BEGIN:STANDARD
    #|DTSTART:19671029T020000
    #|RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10
    #|TZOFFSETFROM:-0400
    #|TZOFFSETTO:-0500
    #|TZNAME:EST
    #|END:STANDARD
    #|BEGIN:DAYLIGHT
    #|DTSTART:19870405T020000
    #|RRULE:FREQ=YEARLY;BYEASTER=400
    #|TZOFFSETFROM:-0500
    #|TZOFFSETTO:-0400
    #|TZNAME:EDT
    #|END:DAYLIGHT
    #|END:VTIMEZONE
  let tzc = @tzical.TzIcal::from_string(s).get().unwrap()
  for d in [dt(2003, 7, 1, tz=tzc), dt(1960, 1, 1, tz=tzc)] {
    // repeated queries give the same answer
    for _ in 0..<2 {
      debug_inspect(
        d.utcoffset(),
        content=(
          #|Some("datetime.timedelta(days=-1, seconds=68400)")
        ),
      )
      debug_inspect(
        d.dst(),
        content=(
          #|Some("datetime.timedelta(0)")
        ),
      )
      debug_inspect(d.tzname(), content="Some(\"EST\")")
    }
  }
}
