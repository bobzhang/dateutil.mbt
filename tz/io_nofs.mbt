///|
/// Whether this backend can read zone files from the file system.
let has_filesystem : Bool = false

///|
/// There is no file system on this backend.
fn is_file(_path : String) -> Bool {
  false
}

///|
fn read_file_bytes(path : String) -> Bytes raise IOError {
  raise IOError("no file system on this backend: \{path}")
}
