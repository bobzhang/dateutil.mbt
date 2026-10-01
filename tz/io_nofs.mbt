// The wasm backends have no portable file system: `@fs` there needs
// host-provided imports, so zone files are not read at all and `gettz`
// only understands TZ strings, "UTC"/"GMT" and the local zone.

///|
/// There is no file system on this backend.
fn is_file(_path : String) -> Bool {
  false
}

///|
fn read_file_bytes(path : String) -> Bytes raise IOError {
  // Only the error type of `@fs` is used here (no host imports).
  let err : @fs.IOError = @fs.IOError("no file system on this backend: \{path}")
  match err {
    @fs.IOError(msg) => raise IOError(msg)
  }
}
