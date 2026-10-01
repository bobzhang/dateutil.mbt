// Port of dateutil/utils.py: general convenience functions for datetimes.

///|
/// `today` given a `datetime.now(tz)` implementation (factored out so the
/// clock can be frozen in tests).
fn today_with(
  now : (@datetime.Tz?) -> @datetime.DateTime,
  tzinfo : @datetime.Tz?,
) -> @datetime.DateTime {
  let dt = now(tzinfo)
  // datetime.combine(dt.date(), time(0, tzinfo=tzinfo))
  dt.date().to_datetime().with_tzinfo(tzinfo)
}

///|
/// `dateutil.utils.today(tzinfo=None)`: the current day at midnight.
/// `tzinfo` is attached to the result and also used to determine the
/// current day; without it the result is naive local time.
pub fn today(tzinfo? : @datetime.Tz) -> @datetime.DateTime {
  today_with(tz => @datetime.DateTime::now(tz?), tzinfo)
}

///|
/// `dateutil.utils.default_tzinfo(dt, tzinfo)`: attach `tzinfo` to `dt`
/// only if `dt` is naive; aware datetimes are returned unchanged.
///
/// ```mbt check
/// test {
///   let dflt = @tz.tzoffset(Some("EST"), -18000)
///   let naive = @datetime.DateTime::new(2014, 1, 1, hour=12, minute=30)
///   inspect(
///     @utils.default_tzinfo(naive, dflt),
///     content="2014-01-01 12:30:00-05:00",
///   )
///   let aware = naive.with_tzinfo(Some(@tz.utc))
///   inspect(
///     @utils.default_tzinfo(aware, dflt),
///     content="2014-01-01 12:30:00+00:00",
///   )
/// }
/// ```
pub fn default_tzinfo(
  dt : @datetime.DateTime,
  tzinfo : @datetime.Tz,
) -> @datetime.DateTime {
  match dt.tzinfo {
    Some(_) => dt
    None => dt.with_tzinfo(Some(tzinfo))
  }
}

///|
/// `dateutil.utils.within_delta(dt1, dt2, delta)`: whether `dt1` and `dt2`
/// differ by at most `abs(delta)`. Raises `TypeError` when mixing naive and
/// aware datetimes, and `OverflowError` when `-abs(delta)` overflows (e.g.
/// `timedelta.max`), as in Python.
///
/// ```mbt check
/// test {
///   let d1 = @datetime.DateTime::new(
///     2016,
///     1,
///     1,
///     hour=12,
///     minute=14,
///     second=1,
///     microsecond=9,
///   )
///   let d2 = d1.replace(microsecond=15)
///   assert_true(@utils.within_delta(d1, d2, @datetime.TimeDelta::new(seconds=1)))
///   assert_false(
///     @utils.within_delta(d1, d2, @datetime.TimeDelta::new(microseconds=1)),
///   )
/// }
/// ```
pub fn within_delta(
  dt1 : @datetime.DateTime,
  dt2 : @datetime.DateTime,
  delta : @datetime.TimeDelta,
) -> Bool raise @datetime.DateTimeError {
  let delta = if delta.days < 0 { delta.checked_neg() } else { delta }
  let difference = dt1.diff(dt2)
  delta.checked_neg() <= difference && difference <= delta
}
