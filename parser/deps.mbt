// Zone constructors provided by the `tz` package.

///|
/// `tz.tzstr(s)` for `tzinfos` entries given as TZ strings.
///
/// TODO(dep): call `@tz.tzstr(s)` once the tz package provides it.
fn tzstr(s : String) -> @datetime.Tz raise {
  raise @datetime.ValueError("tz.tzstr is not available yet: \{s}")
}

///|
/// `tz.tzlocal()`, used when the parsed zone name is a local zone name.
///
/// TODO(dep): call `@tz.tzlocal()` once the tz package provides it.
fn tzlocal() -> @datetime.Tz raise {
  raise @datetime.ValueError("tz.tzlocal is not available yet")
}
