// System local time on the wasm, wasm-gc and js backends, with glibc
// semantics: the zone named by `TZ` (unset: /etc/localtime; empty: UTC; a
// TZif file under TZDIR or the zoneinfo directories, else a POSIX TZ
// string; anything else: UTC) is resolved once and cached until `tzset()`.
// Zone data is evaluated by `internal/tzdata`; files and environment
// variables come from `internal/host`.

///|
priv enum LocalSource {
  /// Zone data evaluated by `internal/tzdata`.
  Zone(@tzdata.Zone)
  /// js without a file system (browsers): the host `Date` object.
  HostDate
}

///|
let local_source : Ref[LocalSource?] = { val: None, }

///|
fn resolve_local_source(tz : String?, can_read_files : Bool) -> LocalSource {
  if can_read_files {
    let (zone, _) = @tzdata.resolve(
      tz,
      read_file=@host.read_file,
      tzdir?=@host.getenv("TZDIR"),
    )
    return Zone(zone)
  }
  // No file system (js outside Node): a POSIX TZ string still works;
  // otherwise ask the host's `Date` (approximate, see `localtime`).
  match tz {
    Some("") => Zone(@tzdata.utc)
    Some(value) => {
      let value = if value.has_prefix(":") {
        value.view(start_offset=1).to_owned()
      } else {
        value
      }
      match @tzdata.parse_posix_tz(value) {
        Some(p) => Zone(PosixZone(p))
        None => HostDate
      }
    }
    None => HostDate
  }
}

///|
fn current_local_source() -> LocalSource {
  match local_source.val {
    Some(s) => s
    None => {
      let s = resolve_local_source(@host.getenv("TZ"), @host.can_read_files())
      local_source.val = Some(s)
      s
    }
  }
}

///|
fn zone_localtime(zone : @tzdata.Zone, t : Int64) -> LocalTime {
  let ty = zone.lookup(t)
  let (year, month, day, hour, minute, second) = @tzdata.civil_from_seconds(
    t + ty.offset.to_int64(),
  )
  {
    year: year.to_int(),
    month,
    day,
    hour,
    minute,
    second,
    isdst: ty.isdst.to_int(),
    gmtoff: ty.offset,
    zone: ty.abbr,
  }
}

///|
fn platform_localtime(t : Int64) -> LocalTime {
  match current_local_source() {
    Zone(zone) => zone_localtime(zone, t)
    HostDate => host_date_localtime(t)
  }
}

///|
fn platform_tzset() -> Unit {
  local_source.val = None
}
