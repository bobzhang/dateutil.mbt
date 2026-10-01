// System local time under various TZ values, on every backend (libc on
// native, internal/tzdata on wasm, wasm-gc and js). Expected values from
// CPython `time.localtime` with `TZ` set and `time.tzset()`.

///|
fn lt_str(t : Int64) -> String {
  let lt = @datetime.localtime(t)
  "\{lt.year}-\{lt.month}-\{lt.day} \{lt.hour}:\{lt.minute}:\{lt.second} isdst=\{lt.isdst} \{lt.gmtoff} \{lt.zone}"
}

///|
test "local time: Europe/London 1941 and BST" {
  for tz in ["Europe/London", ":Europe/London"] {
    with_tz(tz, () => {
      // 1941-01-15 12:00 UTC: British Summer Time all winter
      inspect(lt_str(-913896000L), content="1941-1-15 13:0:0 isdst=1 3600 BST")
      // 1941-07-15 12:00 UTC: double summer time
      inspect(lt_str(-898257600L), content="1941-7-15 14:0:0 isdst=1 7200 BDST")
      inspect(lt_str(1719835200L), content="2024-7-1 13:0:0 isdst=1 3600 BST")
      // before the first transition (local mean time) and after 2038
      inspect(lt_str(-5000000000L), content="1811-7-23 15:5:25 isdst=0 -75 LMT")
      inspect(lt_str(4102444800L), content="2100-1-1 0:0:0 isdst=0 0 GMT")
      inspect(lt_str(4118083200L), content="2100-7-1 1:0:0 isdst=1 3600 BST")
      debug_inspect(
        @datetime.local_zone(),
        content=(
          #|{
          #|  timezone: 0,
          #|  altzone: -3600,
          #|  daylight: true,
          #|  tzname: ("GMT", "BST"),
          #|}
        ),
      )
    })
  }
}

///|
test "local time: POSIX TZ strings, southern hemisphere" {
  with_tz("AEST-10AEDT,M10.1.0,M4.1.0/3", () => {
    inspect(lt_str(1704067200L), content="2024-1-1 11:0:0 isdst=1 39600 AEDT")
    inspect(lt_str(1719835200L), content="2024-7-1 22:0:0 isdst=0 36000 AEST")
    debug_inspect(
      @datetime.local_zone(),
      content=(
        #|{
        #|  timezone: -36000,
        #|  altzone: -39600,
        #|  daylight: true,
        #|  tzname: ("AEST", "AEDT"),
        #|}
      ),
    )
  })
  with_tz("<+0545>-5:45", () => {
    inspect(lt_str(0L), content="1970-1-1 5:45:0 isdst=0 20700 +0545")
  })
}

///|
test "local time: empty or unresolvable TZ is UTC" {
  for tz in ["", "Nowhere/Zone", "no-offset"] {
    with_tz(tz, () => {
      inspect(lt_str(1719835200L), content="2024-7-1 12:0:0 isdst=0 0 UTC")
      debug_inspect(
        @datetime.local_zone(),
        content=(
          #|{ timezone: 0, altzone: 0, daylight: false, tzname: ("UTC", "UTC") }
        ),
      )
    })
  }
}

///|
test "local time: tzset re-reads TZ" {
  with_tz("JST-9", () => {
    inspect(lt_str(0L), content="1970-1-1 9:0:0 isdst=0 32400 JST")
    @env.set_env_var("TZ", "EST5")
    @datetime.tzset()
    inspect(lt_str(0L), content="1969-12-31 19:0:0 isdst=0 -18000 EST")
  })
}

///|
test "local time: from_timestamp/timestamp before 1901 and after 2038" {
  with_tz("America/New_York", () => {
    let cases : Array[(Double, String)] = [
      (-2208988800.0, "datetime.datetime(1899, 12, 31, 19, 0)"),
      (-3000000000.0, "datetime.datetime(1874, 12, 7, 13, 43, 58)"),
      (4294967296.0, "datetime.datetime(2106, 2, 7, 1, 28, 16)"),
      (4307927296.0, "datetime.datetime(2106, 7, 7, 2, 28, 16)"),
      // 2100-11-07 01:30 EDT, then 01:30 EST (fold=1)
      (4129248600.0, "datetime.datetime(2100, 11, 7, 1, 30)"),
      (4129252200.0, "datetime.datetime(2100, 11, 7, 1, 30, fold=1)"),
    ]
    for case in cases {
      let (t, expected) = case
      let d = @datetime.DateTime::from_timestamp(t)
      assert_eq(d.repr(), expected)
      assert_eq(d.timestamp(), t)
    }
  })
}
