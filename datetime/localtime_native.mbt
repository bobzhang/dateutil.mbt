///|
#borrow(out)
extern "c" fn c_localtime(t : Int64, out : FixedArray[Int]) -> Int = "dateutil_localtime"

///|
extern "c" fn c_localtime_zone(t : Int64) -> Bytes = "dateutil_localtime_zone"

///|
extern "c" fn c_tzset() = "dateutil_tzset"

///|
fn platform_localtime(t : Int64) -> LocalTime {
  let out = FixedArray::make(8, 0)
  if c_localtime(t, out) == 0 {
    return gmtime(t)
  }
  let zone_bytes = c_localtime_zone(t)
  let zone = String::from_array(zone_bytes.to_array().map(b => b.to_char()))
  {
    year: out[0],
    month: out[1],
    day: out[2],
    hour: out[3],
    minute: out[4],
    second: out[5],
    isdst: out[6],
    gmtoff: out[7],
    zone,
  }
}

///|
fn platform_tzset() -> Unit {
  c_tzset()
}
