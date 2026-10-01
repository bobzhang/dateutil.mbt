///|
/// rrule re-exports the shared weekday type and the constants `mo`..`su`
/// (Python `MO`..`SU`).
pub using @datetime {type Weekday, mo, tu, we, th, fr, sa, su}

///|
/// The seven plain weekdays, indexed by `Weekday.weekday` (Python
/// `rrule.weekdays`).
pub let weekdays : FixedArray[Weekday] = [mo, tu, we, th, fr, sa, su]

///|
/// rrule's `weekday(wkday, n=None)` constructor: unlike the base
/// `@datetime.Weekday::new` it rejects `n == 0` (Python `ValueError`).
///
/// ```mbt check
/// test {
///   inspect(@rrule.weekday(4, n=-1), content="FR(-1)")
///   try @rrule.weekday(4, n=0) catch {
///     e => inspect(e, content="ValueError: Can't create weekday with n==0")
///   } noraise {
///     _ => fail("expected ValueError")
///   }
/// }
/// ```
pub fn weekday(wkday : Int, n? : Int) -> Weekday raise @datetime.DateTimeError {
  if n is Some(0) {
    raise @datetime.ValueError("Can't create weekday with n==0")
  }
  if wkday < 0 || wkday > 6 {
    raise @datetime.ValueError("weekday must be in 0..6")
  }
  Weekday::new(wkday, n?)
}

///|
/// Python `wday(n)` for rrule weekdays (e.g. `TU(+1)`, `FR(-1)`): the same
/// weekday with occurrence `n`. Returns `wday` itself when `n` already
/// matches, and raises `ValueError` for `n == 0` (even when `wday` is a
/// shared `Weekday` that already has `n == 0`, which rrule's own
/// constructor can never produce).
///
/// ```mbt check
/// test {
///   inspect(@rrule.nth(@rrule.tu, 1), content="TU(+1)")
///   inspect(@rrule.nth(@rrule.th, -2), content="TH(-2)")
/// }
/// ```
pub fn nth(wday : Weekday, n : Int) -> Weekday raise @datetime.DateTimeError {
  if n == 0 {
    raise @datetime.ValueError("Can't create weekday with n==0")
  }
  if wday.n == Some(n) {
    wday
  } else {
    weekday(wday.weekday, n~)
  }
}
