// wasm, wasm-gc and native: `moonbitlang/x/fs`. On the wasm backends this
// needs the `__moonbit_fs_unstable` host imports (provided by moon's
// runner); they are only linked when a file is actually read.

///|
/// Whether this host can read files at all.
pub fn can_read_files() -> Bool {
  true
}

///|
/// Like `read_file`, but with the host's error message on failure.
pub fn read_file_result(path : String) -> Result[Bytes, String] {
  Ok(@fs.read_file_to_bytes(path)) catch {
    @fs.IOError(msg) => Err(msg)
  }
}

///|
/// Python `os.path.isfile`: `path` exists and is a regular file.
pub fn is_file(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}
