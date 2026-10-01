// Native only: cross-check the pure engine used on wasm/wasm-gc/js
// (internal/tzdata, resolved like glibc) against the C library's
// `localtime_r` for many zones and instants.

///|
fn engine_localtime(zone : @tzdata.Zone, t : Int64) -> String {
  let ty = zone.lookup(t)
  let (y, mo, d, h, mi, s) = @tzdata.civil_from_seconds(
    t + ty.offset.to_int64(),
  )
  "\{y}-\{mo}-\{d} \{h}:\{mi}:\{s} isdst=\{ty.isdst.to_int()} \{ty.offset} \{ty.abbr}"
}

///|
fn sample_instants(from : Int64) -> Array[Int64] {
  let ts = []
  // every 9 days and 7 hours from `from` to 2045, plus far instants
  for t = from; t < 2366841600L; t = t + 9L * 86400L + 7L * 3600L {
    ts.push(t)
  }
  for t in [4102444800L, 4118083200L, 7258118400L, 16725225600L] {
    ts.push(t)
  }
  ts
}

///|
fn check_against_libc(tz : String, from : Int64) -> Unit raise {
  let (zone, _) = @tzdata.resolve(Some(tz), read_file=@host.read_file)
  with_tz(tz, () => {
    for t in sample_instants(from) {
      let expected = lt_str(t)
      let got = engine_localtime(zone, t)
      if got != expected {
        fail("TZ=\{tz} at \{t}: libc \{expected}, engine \{got}")
      }
    }
  })
}

///|
test "engine vs libc: zone files" {
  for
    tz in [
      "America/New_York", "America/Los_Angeles", "America/Sao_Paulo", "America/St_Johns",
      "America/Santiago", "America/Havana", "Europe/London", "Europe/Dublin", "Europe/Paris",
      "Europe/Moscow", "Europe/Lisbon", "Africa/Casablanca", "Africa/Cairo", "Asia/Tehran",
      "Asia/Kolkata", "Asia/Kathmandu", "Asia/Shanghai", "Asia/Tokyo", "Asia/Gaza",
      "Australia/Sydney", "Australia/Lord_Howe", "Pacific/Auckland", "Pacific/Chatham",
      "Pacific/Apia", "Pacific/Kiritimati", "Antarctica/Troll", "UTC", "EST5EDT",
      ":Europe/Berlin",
    ] {
    // from 1890: before most zones' first transition
    check_against_libc(tz, -2524521600L)
  }
}

///|
test "engine vs libc: POSIX TZ strings" {
  // The host libc may apply POSIX rules only from 1970 on (macOS) and may
  // not implement RFC 9636 extensions, so only standard strings after 1971.
  for
    tz in [
      "EST5EDT4,M3.2.0/2,M11.1.0/2", "AEST-10AEDT,M10.1.0,M4.1.0/3", "IST-1GMT0,M10.5.0,M3.5.0/1",
      "<+0330>-3:30<+0430>,J79/24,J263/24", "CST6CDT,J60/2,J300/2", "CST6CDT,59/2,299/2",
      "JST-9", "<-0230>2:30", "NZST-12NZDT,M9.5.0,M4.1.0/3",
    ] {
    check_against_libc(tz, 31536000L)
  }
}
