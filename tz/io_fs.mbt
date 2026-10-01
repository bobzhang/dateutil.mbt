///|
/// Whether this backend can read zone files from the file system.
let has_filesystem : Bool = true

///|
/// Python `os.path.isfile`.
fn is_file(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
fn read_file_bytes(path : String) -> Bytes raise IOError {
  @fs.read_file_to_bytes(path) catch {
    @fs.IOError(msg) => raise IOError(msg)
  }
}
