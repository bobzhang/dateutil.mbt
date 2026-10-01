// Upstream rrulestr tests that resolve TZIDs through `tz.gettz` (system
// zoneinfo files: native and js only).

///|
fn gettz(name : String) -> @datetime.Tz raise {
  @tz.gettz(name~).unwrap()
}

///|
test "RRuleTest.testStrWithTZID" {
  let nyc = gettz("America/New_York")
  assert_eq(
    @rrule.rrulestr(
      "DTSTART;TZID=America/New_York:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=3\n",
    ).to_array(),
    [
      dt(1997, 9, 2, h=9, tz=nyc),
      dt(1998, 9, 2, h=9, tz=nyc),
      dt(1999, 9, 2, h=9, tz=nyc),
    ],
  )
}

///|
test "RRuleTest.testStrWithTZIDMapping" {
  let rrstr = "DTSTART;TZID=Eastern:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=3"
  let nyc = gettz("America/New_York")
  let rr = @rrule.rrulestr(rrstr, tzids=Table({ "Eastern": nyc }))
  let exp = [
    dt(1997, 9, 2, h=9, tz=nyc),
    dt(1998, 9, 2, h=9, tz=nyc),
    dt(1999, 9, 2, h=9, tz=nyc),
  ]
  assert_eq(rr.to_array(), exp)
}

///|
test "RRuleTest.testStrWithConflictingTZID" {
  // RFC 5545 Section 3.3.5, FORM #2: DATE WITH UTC TIME
  // The "TZID" property parameter MUST NOT be applied to DATE-TIME
  expect_value_error(() => {
    ignore(
      @rrule.rrulestr(
        "DTSTART;TZID=America/New_York:19970902T090000Z\nRRULE:FREQ=YEARLY;COUNT=3\n",
      ),
    )
  })
}

///|
test "RRuleTest.testStrSetExDateWithTZID" {
  let bxl = gettz("Europe/Brussels")
  let rr = @rrule.rrulestr(
    "DTSTART;TZID=Europe/Brussels:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=6;BYDAY=TU,TH\nEXDATE;TZID=Europe/Brussels:19970904T090000\nEXDATE;TZID=Europe/Brussels:19970911T090000\nEXDATE;TZID=Europe/Brussels:19970918T090000\n",
  )
  assert_eq(rr.to_array(), [
    dt(1997, 9, 2, h=9, tz=bxl),
    dt(1997, 9, 9, h=9, tz=bxl),
    dt(1997, 9, 16, h=9, tz=bxl),
  ])
}

///|
test "RRuleTest.testStrSetExDateValueDateTimeWithTZID" {
  let bxl = gettz("Europe/Brussels")
  let rrstr = [
    "DTSTART;VALUE=DATE-TIME;TZID=Europe/Brussels:19970902T090000", "RRULE:FREQ=YEARLY;COUNT=4;BYDAY=TU,TH",
    "EXDATE;VALUE=DATE-TIME;TZID=Europe/Brussels:19970902T090000", "EXDATE;VALUE=DATE-TIME;TZID=Europe/Brussels:19970909T090000",
  ].join("\n")
  let rr = @rrule.rrulestr(rrstr)
  assert_eq(rr.to_array(), [
    dt(1997, 9, 4, h=9, tz=bxl),
    dt(1997, 9, 11, h=9, tz=bxl),
  ])
}

///|
test "RRuleTest.testStrUntilMustBeUTC" {
  expect_value_error(() => {
    ignore(
      @rrule.rrulestr(
        "DTSTART;TZID=America/New_York:19970902T090000\nRRULE:FREQ=YEARLY;UNTIL=19990101T000000;BYDAY=1TU,-1TH\n",
      ).to_array(),
    )
  })
}

///|
test "RRuleTest.testStrUntilWithTZ" {
  let nyc = gettz("America/New_York")
  let rr = @rrule.rrulestr(
    "DTSTART;TZID=America/New_York:19970101T000000\nRRULE:FREQ=YEARLY;UNTIL=19990101T000000Z\n",
  ).to_array()
  assert_eq(rr, [dt(1997, 1, 1, tz=nyc), dt(1998, 1, 1, tz=nyc)])
}
