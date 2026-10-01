// System local zone resolution with glibc semantics. The file system is
// injected (`read_file`), so this package stays pure and the logic can be
// tested deterministically.

///|
/// Directories searched for a relative zone name after `TZDIR`.
pub let zoneinfo_dirs : Array[String] = [
  "/usr/share/zoneinfo", "/usr/lib/zoneinfo", "/usr/share/lib/zoneinfo", "/etc/zoneinfo",
]

///|
/// The file consulted when `TZ` is unset.
pub let default_localtime_path : String = "/etc/localtime"

///|
/// Where a resolved zone came from.
pub(all) enum ZoneSource {
  /// TZif data read from this path.
  File(String)
  /// The `TZ` value parsed as a POSIX TZ string.
  Posix
  /// Nothing usable: UTC.
  Fallback
} derive(Eq, Debug)

///|
/// Load and decode the TZif file at `path`; `None` if it cannot be read or
/// is not valid TZif.
pub fn load_tzif(path : String, read_file : (String) -> Bytes?) -> Tzif? {
  guard read_file(path) is Some(bytes) else { return None }
  Some(parse_tzif(bytes)) catch {
    _ => None
  }
}

///|
/// The candidate files for a `TZ` value (colon already stripped): the
/// path itself if absolute, else `name` under `TZDIR` and the standard
/// zoneinfo directories.
pub fn zone_file_candidates(name : String, tzdir? : String) -> Array[String] {
  if name.has_prefix("/") {
    return [name]
  }
  let dirs = []
  if tzdir is Some(d) && d != "" {
    dirs.push(d)
  }
  for d in zoneinfo_dirs {
    if !dirs.contains(d) {
      dirs.push(d)
    }
  }
  dirs.map(d => if d.has_suffix("/") { d + name } else { d + "/" + name })
}

///|
/// Resolve the system local zone from the value of `TZ` (glibc rules):
///
/// * unset: `/etc/localtime`;
/// * empty: UTC;
/// * otherwise, after stripping one leading `:`, a TZif file (absolute
///   path, or relative to `TZDIR` / the zoneinfo directories), else a
///   POSIX TZ string;
/// * anything unresolvable: UTC (abbreviation `"UTC"`).
///
/// ```mbt check
/// test {
///   let no_files = (_ : String) => None
///   let (z, src) = @tzdata.resolve(Some(":JST-9"), read_file=no_files)
///   debug_inspect(src, content="Posix")
///   inspect(z.lookup(0).offset, content="32400")
///   let (z, src) = @tzdata.resolve(Some("Nowhere/Zone"), read_file=no_files)
///   debug_inspect(src, content="Fallback")
///   inspect(z.lookup(0).abbr, content="UTC")
/// }
/// ```
pub fn resolve(
  tz : String?,
  read_file~ : (String) -> Bytes?,
  tzdir? : String,
) -> (Zone, ZoneSource) {
  match tz {
    None =>
      match load_tzif(default_localtime_path, read_file) {
        Some(z) => (TzifZone(z), File(default_localtime_path))
        None => (utc, Fallback)
      }
    Some("") => (utc, Fallback)
    Some(value) => {
      let name = if value.has_prefix(":") {
        value.view(start_offset=1).to_owned()
      } else {
        value
      }
      if name != "" {
        for path in zone_file_candidates(name, tzdir?) {
          if load_tzif(path, read_file) is Some(z) {
            return (TzifZone(z), File(path))
          }
        }
      }
      match parse_posix_tz(name) {
        Some(p) => (PosixZone(p), Posix)
        None => (utc, Fallback)
      }
    }
  }
}
