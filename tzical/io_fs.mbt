///|
/// Read a file through `internal/host` (see tz/io_fs.mbt).
fn read_file_text(path : String) -> String raise @tz.IOError {
  let bytes = match @host.read_file_result(path) {
    Ok(bytes) => bytes
    Err(msg) => raise @tz.IOError(msg)
  }
  @utf8.decode_lossy(bytes)
}
