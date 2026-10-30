// Helpers shared by the (generated and hand-written) black-box tests.

///|
/// Python `datetime(y, m, d, h, mi, s, us)` (naive).
fn dt(
  y : Int32,
  m : Int32,
  d : Int32,
  h~ : Int32 = 0,
  mi~ : Int32 = 0,
  s~ : Int32 = 0,
  us~ : Int32 = 0,
  tz? : @datetime.Tz,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  @datetime.DateTime::new(
    y,
    m,
    d,
    hour=h,
    minute=mi,
    second=s,
    microsecond=us,
    tzinfo?=tz,
  )
}

///|
/// Python `date(y, m, d)` as accepted by `rrule` (converted with
/// `datetime.fromordinal(d.toordinal())`).
fn date(
  y : Int32,
  m : Int32,
  d : Int32,
) -> @datetime.DateTime raise @datetime.DateTimeError {
  @datetime.Date::new(y, m, d).to_datetime()
}

///|
/// Upstream `_rrulestr_reverse_test`: `str(rule)` parses back into a rule
/// with the same occurrences.
fn rrulestr_reverse_test(rule : @rrule.Rrule) -> Unit raise {
  let rr_str = rule.to_string()
  let rrulestr_rrule = @rrule.rrulestr(rr_str)
  assert_eq(rule.to_array(), rrulestr_rrule.to_array())
}

///|
/// Upstream `assertRaises(ValueError, ...)`.
fn expect_value_error(f : () -> Unit raise) -> Unit raise {
  try f() catch {
    @datetime.ValueError(_) | @parser.ParserError(_, _) => ()
    e => fail("expected ValueError, got \{e}")
  } noraise {
    _ => fail("expected ValueError")
  }
}
