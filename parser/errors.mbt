///|
/// dateutil `ParserError` (a `ValueError` subclass in Python): raised for
/// invalid or unknown string formats, or if an invalid date would be
/// created.
///
/// The payload mirrors Python's `args`: a `%s` format and the argument
/// substituted into it (the input string). `Show` is Python's `str(e)`;
/// `repr()` is Python's `repr(e)`.
///
/// ```mbt check
/// test {
///   let e = @parser.ParserError("Problem with string: %s", "2019-01-01")
///   inspect(e, content="Problem with string: 2019-01-01")
///   inspect(
///     e.repr(),
///     content="ParserError('Problem with string: %s', '2019-01-01')",
///   )
/// }
/// ```
pub(all) suberror ParserError {
  ParserError(String, String)
} derive(Eq)

///|
/// Python `fmt % (arg,)` for a format containing `%s` placeholders (and
/// `%%`). Falls back to `str(args)` when the format does not take exactly
/// one argument, like `ParserError.__str__`.
fn percent_format(fmt : String, arg : String) -> String {
  let sb = StringBuilder()
  let chars = fmt.to_array()
  let mut used = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '%' && i + 1 < chars.length() && chars[i + 1] == 's' {
      used += 1
      sb.write_string(arg)
      i += 2
    } else if c == '%' && i + 1 < chars.length() && chars[i + 1] == '%' {
      sb.write_char('%')
      i += 2
    } else if c == '%' {
      used = -1
      break
    } else {
      sb.write_char(c)
      i += 1
    }
  }
  if used == 1 {
    sb.to_string()
  } else {
    "(\{@datetime.py_str_repr(fmt)}, \{@datetime.py_str_repr(arg)})"
  }
}

///|
pub impl Show for ParserError with fn output(self, logger) {
  match self {
    ParserError(fmt, arg) => logger.write_string(percent_format(fmt, arg))
  }
}

///|
/// Python `repr(e)`.
pub fn ParserError::repr(self : ParserError) -> String {
  match self {
    ParserError(fmt, arg) => "ParserError('\{fmt}', '\{arg}')"
  }
}

///|
pub impl Debug for ParserError with fn to_repr(self) {
  Repr(self.repr())
}

///|
pub extend ParserError with Show::{to_string, output}

///|
/// dateutil `UnknownTimezoneWarning`: the parser found a time zone name it
/// cannot turn into a zone (pass `tzinfos` to resolve it). MoonBit has no
/// warnings machinery; `parse` reports it through its `on_warning`
/// callback instead (and otherwise ignores it, returning a naive datetime).
pub struct UnknownTimezoneWarning {
  /// The unrecognised zone name.
  tzname : String
} derive(Eq, Debug)

///|
/// The Python warning message.
pub impl Show for UnknownTimezoneWarning with fn output(self, logger) {
  logger.write_string(
    "tzname \{self.tzname} identified but not understood.  Pass `tzinfos` argument in order to correctly return a timezone-aware datetime.  In a future version, this will raise an exception.",
  )
}

///|
pub extend UnknownTimezoneWarning with Show::{to_string, output}
