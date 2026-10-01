// Minimal, failure-tolerant host access used by the local-time resolver and
// the zone-file readers. Every function degrades to "absent" instead of
// raising, so callers can fall back (to UTC, or to `Date` on js).

///|
/// The value of the environment variable `name`, or `None` if it is unset
/// (or the host has no environment).
pub fn getenv(name : String) -> String? {
  @env.get_env_var(name)
}

///|
/// The contents of the file at `path`, or `None` on any failure (missing
/// file, directory, permission error, or no file system on this host).
pub fn read_file(path : String) -> Bytes? {
  match read_file_result(path) {
    Ok(b) => Some(b)
    Err(_) => None
  }
}
