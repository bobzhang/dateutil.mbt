///|
fn read_file_text(path : String) -> String raise @tz.IOError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(msg) => raise @tz.IOError(msg)
  }
  @utf8.decode_lossy(bytes)
}
