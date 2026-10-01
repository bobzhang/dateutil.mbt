///|
/// Python `rrule.__str__`: an RFC 5545 string (`DTSTART:...\nRRULE:...`)
/// that `rrulestr` parses back into an equivalent rule. Like Python, the
/// `DTSTART` carries no `TZID` and `UNTIL` no `Z` suffix.
pub impl Show for Rrule with fn output(self, logger) {
  logger.write_string(self.dtstart.strftime("DTSTART:%Y%m%dT%H%M%S"))
  logger.write_string("\nRRULE:FREQ=")
  logger.write_string(self.freq.to_string())
  if self.interval != 1 {
    logger.write_string(";INTERVAL=\{self.interval}")
  }
  if self.wkst != 0 {
    logger.write_string(";WKST=")
    logger.write_string(weekday_abbrs[self.wkst])
  }
  if self.count is Some(c) {
    logger.write_string(";COUNT=\{c}")
  }
  if self.until is Some(u) {
    logger.write_string(u.strftime(";UNTIL=%Y%m%dT%H%M%S"))
  }
  let o = self.orig
  fn ints(name : String, xs : Array[Int]?) {
    if xs is Some(xs) && !xs.is_empty() {
      logger.write_string(";\{name}=")
      logger.write_string(xs.map(x => x.to_string()).join(","))
    }
  }

  ints("BYSETPOS", o.bysetpos)
  ints("BYMONTH", o.bymonth)
  ints("BYMONTHDAY", o.bymonthday)
  ints("BYYEARDAY", o.byyearday)
  ints("BYWEEKNO", o.byweekno)
  if o.byweekday is Some(ws) && !ws.is_empty() {
    logger.write_string(";BYDAY=")
    logger.write_string(ws.map(rfc_weekday).join(","))
  }
  ints("BYHOUR", o.byhour)
  ints("BYMINUTE", o.byminute)
  ints("BYSECOND", o.bysecond)
  ints("BYEASTER", o.byeaster)
}

///|
/// RFC 5545 `BYDAY` item: `MO`, `+1TU`, `-1FR`.
fn rfc_weekday(w : Weekday) -> String {
  let name = weekday_abbrs[w.weekday]
  match w.n {
    None | Some(0) => name
    Some(n) => if n > 0 { "+\{n}\{name}" } else { "\{n}\{name}" }
  }
}

///|
let weekday_abbrs : FixedArray[String] = [
  "MO", "TU", "WE", "TH", "FR", "SA", "SU",
]

///|
pub extend Rrule with Show::{to_string, output}

///|
/// Debug output is the RFC string (Python's `repr` is the default object
/// repr, which carries no information).
pub impl Debug for Rrule with fn to_repr(self) {
  Repr(self.to_string())
}
