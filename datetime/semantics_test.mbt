///|
/// A toy fold-aware zone: EST/EDT with only the 2021 transitions, written
/// like a plain Python `tzinfo` subclass (no dateutil helpers).
struct Toy {}

///|
fn toy_dst(dt : @datetime.DateTime?) -> @datetime.TimeDelta? {
  guard dt is Some(dt) else { return None }
  let n = dt.with_tzinfo(None).with_fold(0)
  let start = @datetime.DateTime::new(2021, 3, 14, hour=2) catch {
    _ => panic()
  }
  let end = @datetime.DateTime::new(2021, 11, 7, hour=1) catch { _ => panic() }
  let hour = @datetime.TimeDelta::new(hours=1)
  if start <= n && n < end {
    return Some(hour)
  }
  let end_plus = end.add(hour) catch { _ => panic() }
  if end <= n && n < end_plus && dt.fold == 0 {
    return Some(hour)
  }
  Some(@datetime.zero_timedelta)
}

///|
impl @datetime.TzInfo for Toy with fn utcoffset(_, dt) {
  toy_dst(dt).map(d => @datetime.TimeDelta::new(hours=-5) + d)
}

///|
impl @datetime.TzInfo for Toy with fn dst(_, dt) {
  toy_dst(dt)
}

///|
impl @datetime.TzInfo for Toy with fn tzname(_, dt) {
  match toy_dst(dt) {
    Some(d) if !d.is_zero() => Some("EDT")
    _ => Some("EST")
  }
}

///|
impl @datetime.TzInfo for Toy with fn repr(_) {
  "Toy()"
}

///|
test "PEP 495 comparison and default fromutc" {
  let toy = @datetime.Tz::new(Toy::{ })
  let a = @datetime.DateTime::new(2021, 11, 7, hour=1, minute=30, tzinfo=toy)
  let b = a.replace(fold=1)
  let u = a.astimezone(tz=@datetime.utc)
  inspect(
    u.repr(),
    content="datetime.datetime(2021, 11, 7, 5, 30, tzinfo=datetime.timezone.utc)",
  )
  // inter-zone equality is always false for datetimes in the fold
  inspect(a == u, content="false")
  inspect(b == b.astimezone(tz=@datetime.utc), content="false")
  // ...but ordering still uses the UTC instant
  inspect(a.compare(u), content="0")
  // same zone: wall-clock comparison, fold ignored
  inspect(a == b, content="true")
  inspect(a < b, content="false")
  inspect(b.diff(a), content="0:00:00")
  inspect(
    b.astimezone(tz=@datetime.utc).repr(),
    content="datetime.datetime(2021, 11, 7, 6, 30, tzinfo=datetime.timezone.utc)",
  )
  // CPython's default fromutc is not fold-aware
  inspect(
    b.astimezone(tz=@datetime.utc).astimezone(tz=toy).repr(),
    content="datetime.datetime(2021, 11, 7, 2, 30, tzinfo=Toy())",
  )
  inspect(
    u.astimezone(tz=toy).repr(),
    content="datetime.datetime(2021, 11, 7, 1, 30, tzinfo=Toy())",
  )
  let jst = @datetime.Tz::fixed(@datetime.TimeDelta::new(hours=9), name="JST")
  inspect(
    @datetime.DateTime::new(2021, 7, 1, hour=12, tzinfo=toy)
    .astimezone(tz=jst)
    .repr(),
    content="datetime.datetime(2021, 7, 2, 1, 0, tzinfo=datetime.timezone(datetime.timedelta(seconds=32400), 'JST'))",
  )
  inspect(
    @datetime.DateTime::new(2021, 7, 1, hour=12, tzinfo=toy).strftime(
      "%H:%M %Z %z",
    ),
    content="12:00 EDT -0400",
  )
  // hash agrees with equality across zones
  let h1 = @datetime.DateTime::new(2021, 7, 1, hour=12, tzinfo=toy)
  let h2 = h1.astimezone(tz=jst)
  assert_true(h1 == h2)
  assert_eq(h1.hash(), h2.hash())
}

///|
test "naive vs aware" {
  let naive = @datetime.DateTime::new(2021, 1, 1)
  let aware = @datetime.DateTime::new(2021, 1, 1, tzinfo=@datetime.utc)
  inspect(naive == aware, content="false")
  try naive.checked_compare(aware) catch {
    e =>
      inspect(
        e,
        content="TypeError: can't compare offset-naive and offset-aware datetimes",
      )
  } noraise {
    _ => fail("expected TypeError")
  }
  try naive.diff(aware) catch {
    e =>
      inspect(e, content="TypeError: cannot mix naive and timezone-aware time")
  } noraise {
    _ => fail("expected TypeError")
  }
}

///|
test "validation" {
  try @datetime.DateTime::new(2021, 2, 29) catch {
    e => inspect(e, content="ValueError: day is out of range for month")
  } noraise {
    _ => fail("expected ValueError")
  }
  try @datetime.DateTime::new(10000, 1, 1) catch {
    e => inspect(e, content="ValueError: year 10000 is out of range")
  } noraise {
    _ => fail("expected ValueError")
  }
  try @datetime.max_datetime.add(@datetime.resolution) catch {
    e => inspect(e, content="OverflowError: date value out of range")
  } noraise {
    _ => fail("expected OverflowError")
  }
  try @datetime.Tz::fixed(@datetime.TimeDelta::new(hours=24)) catch {
    e =>
      inspect(
        e,
        content="ValueError: offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24), not datetime.timedelta(days=1).",
      )
  } noraise {
    _ => fail("expected ValueError")
  }
}

///|
test "time objects" {
  let est = @datetime.Tz::fixed(@datetime.TimeDelta::new(hours=-5), name="EST")
  let t = @datetime.Time::new(hour=13, minute=20, tzinfo=est)
  inspect(t, content="13:20:00-05:00")
  inspect(t.strftime("%H%M%Z"), content="1320EST")
  inspect(
    t.repr(),
    content="datetime.time(13, 20, tzinfo=datetime.timezone(datetime.timedelta(days=-1, seconds=68400), 'EST'))",
  )
  let t2 = @datetime.Time::new(hour=18, minute=20, tzinfo=@datetime.utc)
  assert_true(t == t2)
  assert_eq(t.hash(), t2.hash())
  inspect(@datetime.Time::new(hour=1, microsecond=5), content="01:00:00.000005")
  inspect(
    @datetime.Time::new(hour=1, microsecond=5).isoformat(timespec=Milliseconds),
    content="01:00:00.000",
  )
}

///|
test "weekday" {
  inspect(@datetime.mo, content="MO")
  inspect(@datetime.fr.nth(Some(2)), content="FR(+2)")
  inspect(@datetime.su.nth(Some(-1)), content="SU(-1)")
  inspect(@datetime.su.nth(Some(0)), content="SU")
  assert_true(@datetime.su.nth(Some(0)) != @datetime.su)
}
