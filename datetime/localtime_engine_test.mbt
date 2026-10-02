// Behaviour of the MoonBit local-time engine (wasm, wasm-gc, js) for TZ
// values that name no zone file and are not valid POSIX strings. Native
// uses the platform libc instead, which differs here: glibc keeps the
// parsed name prefix as the abbreviation (`TZ=Nowhere/Zone` gives
// "Nowhere" at offset 0) while macOS reports "UTC".

///|
test "local time engine: unresolvable TZ is UTC" {
  for tz in ["Nowhere/Zone", "no-offset"] {
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
