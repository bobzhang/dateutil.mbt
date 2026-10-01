///|
test "read_file: missing file and directory" {
  assert_true(@host.read_file("/nonexistent/dateutil/zone") is None)
  assert_true(@host.read_file("/") is None)
  assert_false(@host.is_file("/nonexistent/dateutil/zone"))
  assert_false(@host.is_file("/"))
  assert_true(@host.read_file_result("/nonexistent/dateutil/zone") is Err(_))
}

///|
test "read_file: a zone file" {
  assert_true(@host.can_read_files())
  assert_true(@host.is_file("/usr/share/zoneinfo/UTC"))
  guard @host.read_file("/usr/share/zoneinfo/UTC") is Some(b) else {
    fail("cannot read /usr/share/zoneinfo/UTC")
  }
  assert_true(b is [b'T', b'Z', b'i', b'f', ..])
}

///|
test "getenv" {
  assert_true(@host.getenv("DATEUTIL_SURELY_UNSET_VARIABLE") is None)
  @env.set_env_var("DATEUTIL_HOST_TEST", "x")
  assert_eq(@host.getenv("DATEUTIL_HOST_TEST"), Some("x"))
  @env.unset_env_var("DATEUTIL_HOST_TEST")
  assert_eq(@host.getenv("DATEUTIL_HOST_TEST"), None)
}
