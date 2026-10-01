///|
/// Never reached: on the wasm backends the host "can read files" (a
/// failing read resolves the zone to UTC instead).
fn host_date_localtime(t : Int64) -> LocalTime {
  gmtime(t)
}
