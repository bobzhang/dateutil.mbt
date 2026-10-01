///|
/// Python `IOError`/`OSError`: a zone file could not be read.
pub(all) suberror IOError {
  IOError(String)
} derive(Eq, Debug)

///|
pub impl Show for IOError with fn output(self, logger) {
  match self {
    IOError(msg) => logger.write_string("IOError: \{msg}")
  }
}

///|
/// Python `os.path.isabs` (POSIX).
fn is_abs_path(path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// Python `os.path.join(a, b)` (POSIX, two components).
fn join_path(a : String, b : String) -> String {
  if is_abs_path(b) {
    b
  } else if a == "" || a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
pub extend IOError with Show::{to_string, output}
