///|
fn zone_from_corpus(name : String) -> @tzdata.Zone raise {
  guard zone_files.get(name) is Some(b64) else { fail("no zone \{name}") }
  TzifZone(@tzdata.parse_tzif(@base64.decode(b64)))
}

///|
fn type_str(ty : @tzdata.TimeType) -> String {
  "\{ty.offset}|\{ty.isdst.to_int()}|\{ty.abbr}"
}

///|
test "differential: TZif zones vs time.localtime" {
  let zones : Map[String, @tzdata.Zone] = Map([])
  let mut n = 0
  for rec in zone_corpus {
    let parts = rec.split("|").map(p => p.to_owned()).collect()
    let name = parts[0]
    let zone = match zones.get(name) {
      Some(z) => z
      None => {
        let z = zone_from_corpus(name)
        zones[name] = z
        z
      }
    }
    let t = @string.parse_int64(parts[1])
    let expected = "\{parts[2]}|\{parts[3]}|\{parts[4]}"
    let got = type_str(zone.lookup(t))
    if got != expected {
      fail("\{name} at \{t}: expected \{expected}, got \{got}")
    }
    n += 1
  }
  assert_true(n > 2000)
}

///|
test "differential: POSIX TZ strings vs time.localtime / zoneinfo" {
  let mut n = 0
  for rec in posix_corpus {
    let parts = rec.split("|").map(p => p.to_owned()).collect()
    guard @tzdata.parse_posix_tz(parts[0]) is Some(p) else {
      fail("cannot parse \{parts[0]}")
    }
    let t = @string.parse_int64(parts[1])
    let expected = "\{parts[2]}|\{parts[3]}|\{parts[4]}"
    let got = type_str(@tzdata.PosixZone(p).lookup(t))
    if got != expected {
      fail(
        "\{parts[0]} at \{t} (\{parts[5]}): expected \{expected}, got \{got}",
      )
    }
    n += 1
  }
  assert_true(n > 300)
}
