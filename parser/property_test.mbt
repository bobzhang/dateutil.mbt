// Ported from dateutil tests/property/test_parser_prop.py and
// test_isoparse_prop.py (hypothesis strategies replaced by a deterministic
// pseudo-random sweep).

///|
priv struct Lcg {
  mut state : UInt64
}

///|
fn Lcg::next(self : Lcg, bound : Int) -> Int {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  ((self.state >> 33).to_int() & 0x7fffffff) % bound
}

///|
test "test_parser_prop::test_convertyear" {
  let info = @parser.ParserInfo::new()
  for n in 100..<=9999 {
    assert_eq(info.convertyear(n), n)
  }
}

///|
test "test_parser_prop::test_convertyear_no_specified_century" {
  let p = @parser.ParserInfo::new()
  for n in -50..<=49 {
    let new_year = p.year + n
    let result = p.convertyear(new_year % 100, century_specified=false)
    assert_eq(result, new_year)
  }
}

///|
test "test_isoparse_prop::test_timespec_auto" {
  // TODO(dep): add gettz('US/Eastern'), 'US/Pacific', 'Australia/Sydney',
  // 'Europe/London' (and the ambiguous US/Eastern examples) once tz.gettz
  // is available; fixed-offset zones cover the offset round trip meanwhile.
  let zones : Array[@datetime.Tz?] = [
    None,
    Some(@tz.utc),
    Some(@tz.tzoffset(None, -18000)),
    Some(@tz.tzoffset(Some("X"), 19800)),
    Some(@tz.tzoffset(None, 86340)),
    Some(@tz.tzoffset(None, -86340)),
  ]
  let rng = { state: 20261001UL, }
  for _ in 0..<3000 {
    let ordinal = 1 + rng.next(@datetime.MAXORDINAL)
    let d = @datetime.Date::from_ordinal(ordinal)
    let us = if rng.next(3) == 0 { 0 } else { rng.next(1000000) }
    let dt = @datetime.DateTime::new(
      d.year,
      d.month,
      d.day,
      hour=rng.next(24),
      minute=rng.next(60),
      second=rng.next(60),
      microsecond=us,
      tzinfo?=zones[rng.next(zones.length())],
    )
    let sep = Int::unsafe_to_char(rng.next(128))
    let dtstr = dt.isoformat(sep~)
    let dt_rt = @parser.isoparse(dtstr)
    // The round trip preserves the wall time and the offset.
    assert_eq(dt_rt.with_tzinfo(None), dt.with_tzinfo(None))
    assert_eq(dt_rt.utcoffset(), dt.utcoffset())
    assert_eq(dt_rt, dt)
  }
}
