///|
pub extend DateTimeError with Show::{to_string, output}

///|
pub extend TimeDelta with Show::{to_string, output}

///|
pub extend TimeDelta with Compare::{compare}

///|
pub extend Date with Show::{to_string, output}

///|
pub extend Date with Compare::{compare}

///|
pub extend Time with Show::{to_string, output}

///|
pub extend Time with Compare::{compare}

///|
pub extend DateTime with Show::{to_string, output}

///|
pub extend DateTime with Compare::{compare}

///|
pub extend Tz with Show::{to_string, output}

///|
pub extend Weekday with Show::{to_string, output}

///|
/// Debug output is the Python `repr()` (as a string).
pub impl Debug for TimeDelta with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub impl Debug for Date with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub impl Debug for Time with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub impl Debug for DateTime with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub impl Debug for Tz with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub impl Debug for Weekday with fn to_repr(self) {
  Repr(self.to_string())
}

///|
pub impl Debug for DateTimeError with fn to_repr(self) {
  Repr(self.to_string())
}
