// Helpers shared by the generated (upstream / differential) parser tests.
// Results are rendered like the Python generators render them: the
// `repr()` of the value, or `"<ExceptionClass>: <str(e)>"`.

///|
fn dt(
  y : Int,
  m : Int,
  d : Int,
  hour? : Int = 0,
  minute? : Int = 0,
  second? : Int = 0,
  microsecond? : Int = 0,
) -> @datetime.DateTime {
  try! @datetime.DateTime::new(y, m, d, hour~, minute~, second~, microsecond~)
}

///|
fn offsets(pairs : Array[(String, Int)]) -> @parser.TzInfos {
  let m = Map([])
  for p in pairs {
    m[p.0] = @parser.Offset(p.1)
  }
  Table(m)
}

///|
fn render_error(e : Error) -> String {
  match e {
    @parser.ParserError(_) as pe => "ParserError: \{pe}"
    @datetime.ValueError(msg) => "ValueError: \{msg}"
    @datetime.OverflowError(msg) => "OverflowError: \{msg}"
    @datetime.TypeError(msg) => "TypeError: \{msg}"
    e => "Error: \{e}"
  }
}

///|
/// Python `repr(tuple_of_str)`.
fn tuple_repr(xs : Array[String]) -> String {
  let parts = xs.map(@datetime.py_str_repr)
  if parts.length() == 1 {
    "(\{parts[0]},)"
  } else {
    "(" + parts.join(", ") + ")"
  }
}

///|
fn check_parse(
  timestr : String,
  expected : String,
  default? : @datetime.DateTime,
  ignoretz? : Bool = false,
  tzinfos? : @parser.TzInfos,
  dayfirst? : Bool,
  yearfirst? : Bool,
  fuzzy? : Bool = false,
  tokens? : Bool = false,
  warns? : Array[String] = [],
  info? : @parser.ParserInfo,
) -> Unit raise {
  let warned = []
  let on_warning = (w : @parser.UnknownTimezoneWarning) => warned.push(w.tzname)
  let actual = try {
    if tokens {
      let (d, toks) = @parser.parse_with_tokens(
        timestr,
        parserinfo?=info,
        default?,
        ignoretz~,
        tzinfos?,
        dayfirst?,
        yearfirst?,
        on_warning~,
      )
      "(\{d.repr()}, \{tuple_repr(toks)})"
    } else {
      @parser.parse(
        timestr,
        parserinfo?=info,
        default?,
        ignoretz~,
        tzinfos?,
        dayfirst?,
        yearfirst?,
        fuzzy~,
        on_warning~,
      ).repr()
    }
  } catch {
    e => render_error(e)
  }
  if actual != expected {
    fail(
      "parse(\{@datetime.py_str_repr(timestr)}): expected \{expected}, got \{actual}",
    )
  }
  if warned != warns {
    fail(
      "parse(\{@datetime.py_str_repr(timestr)}): expected warnings \{warns.join(",")}, got \{warned.join(",")}",
    )
  }
}

///|
fn iso_parser(sep : String?) -> @parser.IsoParser raise {
  match sep {
    None => @parser.IsoParser::new()
    Some(s) => @parser.IsoParser::new(sep=s)
  }
}

///|
fn check_iso_result(
  what : String,
  s : String,
  expected : String,
  f : () -> String raise,
) -> Unit raise {
  let actual = f() catch { e => render_error(e) }
  if actual != expected {
    fail(
      "\{what}(\{@datetime.py_str_repr(s)}): expected \{expected}, got \{actual}",
    )
  }
}

///|
fn check_isoparse(s : String, expected : String, sep? : String) -> Unit raise {
  check_iso_result("isoparse", s, expected, () => {
    iso_parser(sep).isoparse(s).repr()
  })
}

///|
fn check_isodate(s : String, expected : String, sep? : String) -> Unit raise {
  check_iso_result("parse_isodate", s, expected, () => {
    iso_parser(sep).parse_isodate(s).repr()
  })
}

///|
fn check_isotime(s : String, expected : String, sep? : String) -> Unit raise {
  check_iso_result("parse_isotime", s, expected, () => {
    iso_parser(sep).parse_isotime(s).repr()
  })
}

///|
fn check_tzstr(
  s : String,
  expected : String,
  zero_as_utc? : Bool = true,
  sep? : String,
) -> Unit raise {
  check_iso_result("parse_tzstr", s, expected, () => {
    iso_parser(sep).parse_tzstr(s, zero_as_utc~).repr()
  })
}

///|
fn check_isoparser_new(sep : String, expected : String) -> Unit raise {
  check_iso_result("isoparser", sep, expected, () => {
    ignore(@parser.IsoParser::new(sep~))
    "ok"
  })
}
