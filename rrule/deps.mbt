// Dependencies of `rrulestr` on `dateutil.parser` and `dateutil.tz`.

///|
/// `parser.parse(s, ignoretz=ignoretz, tzinfos=tzinfos)` as used by
/// `rrulestr` for DTSTART, UNTIL, RDATE and EXDATE values. Errors propagate
/// unchanged (`@parser.ParserError` for unparsable strings).
fn parse_datetime(
  s : String,
  ignoretz : Bool,
  tzinfos : @parser.TzInfos?,
) -> @datetime.DateTime raise {
  @parser.parse(s, ignoretz~, tzinfos?)
}

///|
/// Whether `e` is a Python `ValueError` (including its subclass
/// `ParserError`).
fn is_value_error(e : Error) -> Bool {
  match e {
    @datetime.ValueError(_) | @parser.ParserError(_, _) => true
    _ => false
  }
}

///|
/// `tz.gettz(name)`, the default `tzids` lookup of `rrulestr`.
fn default_gettz(name : String) -> @datetime.Tz? raise {
  @tz.gettz(name~)
}
