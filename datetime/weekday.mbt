///|
/// A weekday with an optional occurrence count, e.g. `MO`, `FR(+2)`,
/// `SU(-1)` (dateutil's `_common.weekday`). `weekday` is 0 (Monday) .. 6.
pub struct Weekday {
  weekday : Int
  n : Int?
} derive(Eq, Hash)

///|
/// Create a weekday; `weekday` must be in `0..=6`.
pub fn Weekday::new(weekday : Int, n? : Int) -> Weekday {
  if weekday < 0 || weekday > 6 {
    abort("weekday must be in 0..=6, got \{weekday}")
  }
  { weekday, n, }
}

///|
/// Python `weekday.__call__(n)`: the same weekday with occurrence `n`.
pub fn Weekday::nth(self : Weekday, n : Int?) -> Weekday {
  if n == self.n {
    self
  } else {
    { weekday: self.weekday, n, }
  }
}

///|
pub let weekday_abbrs : FixedArray[String] = [
  "MO", "TU", "WE", "TH", "FR", "SA", "SU",
]

///|
/// `MO`, `TU(+1)`, `SU(-2)`; `n == 0` and `None` both print bare.
pub impl Show for Weekday with fn output(self, logger) {
  logger.write_string(weekday_abbrs[self.weekday])
  match self.n {
    None | Some(0) => ()
    Some(n) => logger.write_string(if n > 0 { "(+\{n})" } else { "(\{n})" })
  }
}

///|
pub let mo : Weekday = { weekday: 0, n: None, }

///|
pub let tu : Weekday = { weekday: 1, n: None, }

///|
pub let we : Weekday = { weekday: 2, n: None, }

///|
pub let th : Weekday = { weekday: 3, n: None, }

///|
pub let fr : Weekday = { weekday: 4, n: None, }

///|
pub let sa : Weekday = { weekday: 5, n: None, }

///|
pub let su : Weekday = { weekday: 6, n: None, }
