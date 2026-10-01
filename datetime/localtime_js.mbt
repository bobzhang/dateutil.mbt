///|
extern "js" fn js_localtime(t : Double, out : FixedArray[Int]) -> String =
  #|(t, out) => {
  #|  const d = new Date(t * 1000);
  #|  out[0] = d.getFullYear(); out[1] = d.getMonth() + 1; out[2] = d.getDate();
  #|  out[3] = d.getHours(); out[4] = d.getMinutes(); out[5] = d.getSeconds();
  #|  const y = d.getFullYear();
  #|  const jan = new Date(y, 0, 1).getTimezoneOffset();
  #|  const jul = new Date(y, 6, 1).getTimezoneOffset();
  #|  const off = d.getTimezoneOffset();
  #|  out[6] = (jan !== jul && off === Math.min(jan, jul)) ? 1 : 0;
  #|  out[7] = -off * 60;
  #|  try {
  #|    const p = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short' })
  #|      .formatToParts(d).find((x) => x.type === 'timeZoneName');
  #|    return p ? p.value : '';
  #|  } catch (e) { return ''; }
  #|}

///|
fn platform_localtime(t : Int64) -> LocalTime {
  let out = FixedArray::make(8, 0)
  let zone = js_localtime(t.to_double(), out)
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

}
