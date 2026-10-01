///|
/// Errors raised by the datetime model. The constructors mirror the Python
/// exception classes raised by CPython's `datetime` module.
pub(all) suberror DateTimeError {
  ValueError(String)
  OverflowError(String)
  TypeError(String)
} derive(Eq)

///|
pub impl Show for DateTimeError with fn output(self, logger) {
  match self {
    ValueError(msg) => logger.write_string("ValueError: \{msg}")
    OverflowError(msg) => logger.write_string("OverflowError: \{msg}")
    TypeError(msg) => logger.write_string("TypeError: \{msg}")
  }
}
