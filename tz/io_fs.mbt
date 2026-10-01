// Zone files are read through `internal/host`: `moonbitlang/x/fs` on
// native and wasm, Node's `fs` obtained at run time on js (no static
// `node:fs` import, so browser bundles load; there every read fails).

///|
/// Python `os.path.isfile`.
fn is_file(path : String) -> Bool {
  @host.is_file(path)
}

///|
fn read_file_bytes(path : String) -> Bytes raise IOError {
  match @host.read_file_result(path) {
    Ok(bytes) => bytes
    Err(msg) => raise IOError(msg)
  }
}
