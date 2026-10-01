// Stand-in for `tz.gettz("America/New_York")` on the wasm backends (no
// file system, so no zoneinfo): EST is NYC's offset on every date the
// tests use, and it is equally a distinct zone object.

///|
fn nyc() -> @datetime.Tz raise {
  @tz.tzoffset(Some("EST"), -18000)
}
