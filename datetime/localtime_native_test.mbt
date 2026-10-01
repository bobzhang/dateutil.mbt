///|
fn with_tz(tz : String, f : () -> Unit raise) -> Unit raise {
  let old = @env.get_env_var("TZ")
  @env.set_env_var("TZ", tz)
  @datetime.tzset()
  defer {
    match old {
      Some(v) => @env.set_env_var("TZ", v)
      None => @env.unset_env_var("TZ")
    }
    @datetime.tzset()
  }
  f()
}

///|
test "local time: America/New_York" {
  with_tz("America/New_York", () => {
    let cases : Array[(Double, String)] = [
      (1636264800.0, "datetime.datetime(2021, 11, 7, 1, 0, fold=1)"),
      (1636261200.0, "datetime.datetime(2021, 11, 7, 1, 0)"),
      (1636268400.0, "datetime.datetime(2021, 11, 7, 2, 0)"),
      (1615705200.0, "datetime.datetime(2021, 3, 14, 3, 0)"),
      (0.0, "datetime.datetime(1969, 12, 31, 19, 0)"),
      (1700000000.25, "datetime.datetime(2023, 11, 14, 17, 13, 20, 250000)"),
    ]
    for case in cases {
      let (t, expected) = case
      let d = @datetime.DateTime::from_timestamp(t)
      assert_eq(d.repr(), expected)
      assert_eq(d.timestamp(), t)
    }
    let amb = @datetime.DateTime::new(2021, 11, 7, hour=1, minute=30)
    assert_eq(amb.timestamp(), 1636263000.0)
    assert_eq(amb.replace(fold=1).timestamp(), 1636266600.0)
    let gap = @datetime.DateTime::new(2021, 3, 14, hour=2, minute=30)
    assert_eq(gap.timestamp(), 1615707000.0)
    assert_eq(gap.replace(fold=1).timestamp(), 1615703400.0)
    inspect(
      @datetime.DateTime::new(
        2021,
        11,
        7,
        hour=1,
        minute=30,
        tzinfo=@datetime.utc,
      )
      .astimezone()
      .repr(),
      content="datetime.datetime(2021, 11, 6, 21, 30, tzinfo=datetime.timezone(datetime.timedelta(days=-1, seconds=72000), 'EDT'))",
    )
    inspect(
      @datetime.DateTime::new(2021, 7, 7, hour=1, minute=30)
      .astimezone(tz=@datetime.utc)
      .repr(),
      content="datetime.datetime(2021, 7, 7, 5, 30, tzinfo=datetime.timezone.utc)",
    )
    debug_inspect(
      @datetime.local_zone(),
      content=(
        #|{
        #|  timezone: 18000,
        #|  altzone: 14400,
        #|  daylight: true,
        #|  tzname: ("EST", "EDT"),
        #|}
      ),
    )
  })
}
