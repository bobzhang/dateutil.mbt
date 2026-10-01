// The wasm backends have no portable file system (`@fs` needs host
// imports there); use `TzIcal::from_string` instead.

///|
fn read_file_text(path : String) -> String raise @tz.IOError {
  let _ = @utf8.decode_lossy(b"")
  let err : @fs.IOError = @fs.IOError("no file system on this backend: \{path}")
  match err {
    @fs.IOError(msg) => raise @tz.IOError(msg)
  }
}
