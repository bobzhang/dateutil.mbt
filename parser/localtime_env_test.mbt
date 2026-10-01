// The parser recognises the local zone's names (`time.tzname`) on every
// backend: the system local time comes from libc on native and from the
// internal/tzdata resolver (honouring TZ) on wasm, wasm-gc and js.

///|
fn with_tz(tzval : String, f : () -> Unit raise) -> Unit raise {
  let old = @env.get_env_var("TZ")
  @env.set_env_var("TZ", tzval)
  @datetime.tzset()
  defer {
    match old {
      Some(v) => @env.set_env_var("TZ", v)
      None => @env.unset_env_var("TZ")
    }
    @datetime.tzset()
  }
  f()
}

///|
test "local zone names: BST under TZ=Europe/London" {
  with_tz("Europe/London", () => {
    let d = @parser.parse("2024-07-01 12:00 BST")
    inspect(d.isoformat(), content="2024-07-01T12:00:00+01:00")
    inspect(d.tzinfo is Some(z) && z.to_string() == "tzlocal()", content="true")
    let w = @parser.parse("2024-01-15 12:00 GMT")
    inspect(w.isoformat(), content="2024-01-15T12:00:00+00:00")
  })
}

///|
test "local zone names: AEST/AEDT under a POSIX TZ string" {
  with_tz("AEST-10AEDT,M10.1.0,M4.1.0/3", () => {
    let d = @parser.parse("2024-01-15 12:00 AEDT")
    inspect(d.isoformat(), content="2024-01-15T12:00:00+11:00")
    let d = @parser.parse("2024-07-15 12:00 AEST")
    inspect(d.isoformat(), content="2024-07-15T12:00:00+10:00")
  })
}
