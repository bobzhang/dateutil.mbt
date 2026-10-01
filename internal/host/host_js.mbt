// js: no static `node:fs` import (it would break browser bundles). The
// `fs` module is obtained at run time through `process.getBuiltinModule`
// (Node >= 22.3, Deno, Bun) or a global `require`; without either
// (browsers) no file can be read.

///|
extern "js" fn js_fs_available() -> Bool =
  #|() => {
  #|  try {
  #|    const p = globalThis.process;
  #|    let fs = undefined;
  #|    if (p && typeof p.getBuiltinModule === 'function') fs = p.getBuiltinModule('fs');
  #|    if (!fs && typeof globalThis.require === 'function') fs = globalThis.require('fs');
  #|    return !!(fs && typeof fs.readFileSync === 'function');
  #|  } catch (e) { return false; }
  #|}

///|
/// `status[0]` is set to 1 on success; on failure the error message is
/// stored in `msg[0]` and an empty array is returned.
extern "js" fn js_read_file(
  path : String,
  status : FixedArray[Int],
  msg : FixedArray[String],
) -> Bytes =
  #|(path, status, msg) => {
  #|  status[0] = 0;
  #|  try {
  #|    const p = globalThis.process;
  #|    let fs = undefined;
  #|    if (p && typeof p.getBuiltinModule === 'function') fs = p.getBuiltinModule('fs');
  #|    if (!fs && typeof globalThis.require === 'function') fs = globalThis.require('fs');
  #|    if (!fs || typeof fs.readFileSync !== 'function') {
  #|      msg[0] = 'no file system available';
  #|      return new Uint8Array(0);
  #|    }
  #|    const b = fs.readFileSync(path);
  #|    status[0] = 1;
  #|    return new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
  #|  } catch (e) {
  #|    msg[0] = String(e && e.message !== undefined ? e.message : e);
  #|    return new Uint8Array(0);
  #|  }
  #|}

///|
extern "js" fn js_is_file(path : String) -> Bool =
  #|(path) => {
  #|  try {
  #|    const p = globalThis.process;
  #|    let fs = undefined;
  #|    if (p && typeof p.getBuiltinModule === 'function') fs = p.getBuiltinModule('fs');
  #|    if (!fs && typeof globalThis.require === 'function') fs = globalThis.require('fs');
  #|    if (!fs || typeof fs.statSync !== 'function') return false;
  #|    return fs.statSync(path).isFile();
  #|  } catch (e) { return false; }
  #|}

///|
/// Whether this host can read files at all (Node-like runtimes only).
pub fn can_read_files() -> Bool {
  js_fs_available()
}

///|
/// Like `read_file`, but with the host's error message on failure.
pub fn read_file_result(path : String) -> Result[Bytes, String] {
  let status = FixedArray::make(1, 0)
  let msg = FixedArray::make(1, "")
  let bytes = js_read_file(path, status, msg)
  if status[0] == 1 {
    Ok(bytes)
  } else {
    Err(msg[0])
  }
}

///|
/// Python `os.path.isfile`: `path` exists and is a regular file.
pub fn is_file(path : String) -> Bool {
  js_is_file(path)
}
