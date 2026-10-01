///|
let epoch_ordinal : Int = @datetime.ymd_to_ordinal(1970, 1, 1)

///|
/// dateutil `_datetime_to_timestamp(dt)` in microseconds: the wall time of
/// `dt` (its zone ignored) as microseconds since 1970-01-01.
///
/// dateutil computes a float number of seconds; comparing exact
/// microseconds against integer transition times gives the same answers.
fn naive_timestamp_us(dt : @datetime.DateTime) -> Int64 {
  let days = (dt.to_ordinal() - epoch_ordinal).to_int64()
  let secs = days * 86400L +
    (dt.hour * 3600 + dt.minute * 60 + dt.second).to_int64()
  secs * 1000000L + dt.microsecond.to_int64()
}

///|
/// `floor(_datetime_to_timestamp(dt))` in seconds.
fn naive_timestamp_floor(dt : @datetime.DateTime) -> Int64 {
  let days = (dt.to_ordinal() - epoch_ordinal).to_int64()
  days * 86400L + (dt.hour * 3600 + dt.minute * 60 + dt.second).to_int64()
}
