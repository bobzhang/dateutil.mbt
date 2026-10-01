///|
fn source_str(s : LocalSource) -> String {
  match s {
    Zone(z) => {
      let ty = z.lookup(1719835200L) // 2024-07-01 12:00 UTC
      "zone \{ty.abbr} \{ty.offset}"
    }
    HostDate => "host Date"
  }
}

///|
test "resolve_local_source: without a file system (browsers)" {
  let r = (tz : String?) => source_str(resolve_local_source(tz, false))
  inspect(r(None), content="host Date")
  inspect(r(Some("")), content="zone UTC 0")
  inspect(r(Some("JST-9")), content="zone JST 32400")
  inspect(r(Some(":EST5EDT")), content="zone EDT -14400")
  inspect(r(Some("Europe/London")), content="host Date")
}

///|
test "resolve_local_source: with a file system" {
  let r = (tz : String?) => source_str(resolve_local_source(tz, true))
  inspect(r(Some("")), content="zone UTC 0")
  inspect(r(Some("Europe/London")), content="zone BST 3600")
  inspect(r(Some("Nowhere/Zone")), content="zone UTC 0")
}
