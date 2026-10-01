// dateutil `gettz`: look up a zone by name (IANA key, file path, TZ
// string), with the 2.7.0+ caching semantics.

///|
/// dateutil `TZFILES`: candidate files for the local zone, tried in order
/// by `gettz()` (relative names are looked up in `tzpaths`). Mutable, like
/// the Python module global.
pub let tzfiles : Array[String] = ["/etc/localtime", "localtime"]

///|
/// dateutil `TZPATHS`: directories searched for zoneinfo files. Mutable,
/// like the Python module global.
pub let tzpaths : Array[String] = [
  "/usr/share/zoneinfo", "/usr/lib/zoneinfo", "/usr/share/lib/zoneinfo", "/etc/zoneinfo",
]

///|
/// Errors other than `IOError`/`ValueError` (Python `IOError`, `OSError`,
/// `ValueError`) are not swallowed by `gettz`'s file lookups.
fn is_tzfile_lookup_error(e : Error) -> Bool {
  match e {
    IOError(_) => true
    @datetime.ValueError(_) => true
    _ => false
  }
}

///|
/// `gettz.nocache`: the uncached lookup. The second component tells
/// whether the result is a `tzlocal` (which `gettz` does not cache).
fn gettz_lookup(name : String?) -> (@datetime.Tz?, Bool) raise {
  let mut name = name
  if name is (None | Some("")) {
    if @env.get_env_var("TZ") is Some(v) {
      name = Some(v)
    }
  }
  match name {
    None | Some("" | ":") => {
      for filepath in tzfiles {
        let mut filepath = filepath
        if !is_abs_path(filepath) {
          let filename = filepath
          let found = for path in tzpaths {
            filepath = join_path(path, filename)
            if is_file(filepath) {
              break true
            }
          } nobreak {
            false
          }
          if !found {
            continue
          }
        }
        if is_file(filepath) {
          let tz = tzfile(filepath) catch {
            e if is_tzfile_lookup_error(e) => continue
            e => raise e
          }
          return (Some(tz), false)
        }
      }
      (Some(tzlocal()), true)
    }
    Some(name) => {
      let name = if name.has_prefix(":") {
        name.view(start_offset=1).to_owned()
      } else {
        name
      }
      if is_abs_path(name) {
        if is_file(name) {
          return (Some(tzfile(name)), false)
        } else {
          return (None, false)
        }
      }
      for path in tzpaths {
        let mut filepath = join_path(path, name)
        if !is_file(filepath) {
          filepath = filepath.replace_all(old=" ", new="_")
          if !is_file(filepath) {
            continue
          }
        }
        let tz = tzfile(filepath) catch {
          e if is_tzfile_lookup_error(e) => continue
          e => raise e
        }
        return (Some(tz), false)
      }
      // Not found in the zoneinfo directories. (dateutil would next try
      // Windows zones and its bundled zoneinfo tarball; neither exists
      // here.)
      for c in name {
        // name is not a tzstr unless it has at least one offset
        if c is ('0'..='9') {
          let tz = tzstr(name) catch {
            @datetime.ValueError(_) => return (None, false)
            e => raise e
          }
          return (Some(tz), false)
        }
      }
      if name is ("GMT" | "UTC") {
        (Some(utc), false)
      } else {
        let (std_name, dst_name) = @datetime.local_zone().tzname
        if name == std_name || name == dst_name {
          (Some(tzlocal()), true)
        } else {
          (None, false)
        }
      }
    }
  }
}

///|
/// `gettz.nocache(name)`: a non-cached version of `gettz`; every call
/// builds a new zone.
pub fn gettz_nocache(name? : String) -> @datetime.Tz? raise {
  gettz_lookup(name).0
}

///|
/// The `gettz` cache. Python keeps a weak-value dictionary plus a small
/// LRU of strong references; without weak references every cached zone
/// is kept until `gettz_cache_clear()` (as if the caller still held it).
let gettz_instances : Map[String, @datetime.Tz] = Map([])

///|
/// Python's strong-cache LRU (names, most recent last). It only bounds
/// what a weak dictionary would keep alive, so here it has no observable
/// effect; it is maintained for `gettz_set_cache_size` compatibility.
let gettz_strong_cache : Array[String] = []

///|
let gettz_strong_cache_size : Ref[Int] = Ref(8)

///|
fn gettz_touch_strong(name : String) -> Unit {
  match gettz_strong_cache.search(name) {
    Some(i) => ignore(gettz_strong_cache.remove(i))
    None => ()
  }
  gettz_strong_cache.push(name)
  while gettz_strong_cache.length() > gettz_strong_cache_size.val {
    ignore(gettz_strong_cache.remove(0))
  }
}

///|
/// `gettz(name)`: retrieve a time zone from a string, the way a POSIX `TZ`
/// variable would be interpreted:
///
/// * no name (or `""`): the `TZ` environment variable if set, else the
///   local zone file (`tzfiles`), else `tzlocal()`;
/// * an absolute path (optionally `:`-prefixed): that zoneinfo file;
/// * an IANA key such as `America/New_York`: searched in `tzpaths`;
/// * otherwise a `TZ` string with an offset (`EST5EDT`) via `tzstr`, or
///   `GMT`/`UTC` (`utc`), or a name of the local zone (`tzlocal()`).
///
/// Returns `None` if nothing matches. Repeated calls with the same name
/// return the same zone object (except for local zones and `gettz()`
/// with no name). Raises if an explicit absolute path is not a valid
/// zone file. On backends without a file system only the string forms
/// are available.
///
/// ```mbt check
/// test {
///   let z = @tz.gettz(name="EST5EDT4,M3.2.0/2,M11.1.0/2")
///   guard z is Some(z) else { fail("expected a zone") }
///   assert_true(@tz.gettz(name="EST5EDT4,M3.2.0/2,M11.1.0/2") is Some(z2) && z2.is_same(z))
///   assert_true(@tz.gettz(name="Fake.Region/Abcdefghijklmnop") is None)
/// }
/// ```
pub fn gettz(name? : String) -> @datetime.Tz? raise {
  if name is Some(n) && gettz_instances.get(n) is Some(rv) {
    gettz_touch_strong(n)
    return Some(rv)
  }
  let (rv, is_local) = gettz_lookup(name)
  match (name, rv) {
    (Some(n), Some(tz)) if !is_local => {
      gettz_instances[n] = tz
      gettz_touch_strong(n)
    }
    // No need for caching
    _ => ()
  }
  rv
}

///|
/// `gettz.cache_clear()`: forget all cached zones.
pub fn gettz_cache_clear() -> Unit {
  gettz_instances.clear()
  gettz_strong_cache.clear()
}

///|
/// `gettz.set_cache_size(size)`: the size of Python's strong LRU cache.
/// Without weak references this has no observable effect (see
/// `PORTING.md`).
pub fn gettz_set_cache_size(size : Int) -> Unit {
  gettz_strong_cache_size.val = size
  while gettz_strong_cache.length() > size && gettz_strong_cache.length() > 0 {
    ignore(gettz_strong_cache.remove(0))
  }
}
