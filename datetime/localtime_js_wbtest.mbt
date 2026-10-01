///|
test "host Date fallback (js without a file system) is approximate" {
  let old = @env.get_env_var("TZ")
  @env.set_env_var("TZ", "Europe/London")
  defer (match old {
    Some(v) => @env.set_env_var("TZ", v)
    None => @env.unset_env_var("TZ")
  })
  // 2024-07-01 12:00 UTC: wall time and offset are right ...
  let lt = host_date_localtime(1719835200L)
  debug_inspect(
    (lt.year, lt.month, lt.day, lt.hour, lt.gmtoff, lt.isdst),
    content="(2024, 7, 1, 13, 3600, 1)",
  )
  // ... but 1941 BST in winter is not recognised as DST
  let lt = host_date_localtime(-913896000L)
  debug_inspect((lt.hour, lt.gmtoff, lt.isdst), content="(13, 3600, 0)")
}
