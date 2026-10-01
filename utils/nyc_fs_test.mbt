// `NYC = tz.gettz("America/New_York")` as in upstream tests/test_utils.py
// (native/js: needs the system zoneinfo database).

///|
fn nyc() -> @datetime.Tz raise {
  guard @tz.gettz(name="America/New_York") is Some(z) else {
    fail("gettz(America/New_York) is None")
  }
  z
}
