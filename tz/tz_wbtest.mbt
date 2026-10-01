// White-box tests: tzfile internals and the TZ string parser.

///|
fn wb_zone_bytes(name : String) -> Bytes {
  @base64.decode(wb_zone_data[name]) catch {
    _ => abort("bad base64")
  }
}

///|
/// The outcome of `f()`: `ok(result)` or the Python exception class.
fn outcome(f : () -> String raise) -> String {
  f() catch {
    e => error_kind(e)
  }
}

///|
test "TZTest.testLeapCountDecodesProperly" {
  // The whole TZif v1 file (with leap second records) must be consumed.
  let data = wb_zone_bytes("NEW_YORK")
  let (_, consumed) = read_tzfile(data)
  assert_eq(consumed, data.length())
}

///|
test "TZTest.testIsStd" {
  // NEW_YORK tzfile contains this isstd information:
  let (parsed, _) = read_tzfile(wb_zone_bytes("NEW_YORK"))
  let isstd = parsed.ttinfo_list.map(t => if t.isstd { 1 } else { 0 })
  assert_eq(isstd[0:4].to_owned(), [0, 0, 0, 1])
}

///|
fn rule_repr(r : TzRule) -> String {
  let parts : Array[String] = []
  let add = (name : String, v : Int?) => {
    if v is Some(x) {
      parts.push("\{name}=\{x}")
    }
  }
  add("month", r.month)
  add("week", r.week)
  add("weekday", r.weekday)
  add("yday", r.yday)
  add("jyday", r.jyday)
  add("day", r.day)
  add("time", r.time)
  "_attr(\{parts.join(", ")})"
}

///|
/// Python `repr(_tzparser._result)` plus `any_unused_tokens`.
fn parse_repr(res : TzStrParse) -> String {
  let parts : Array[String] = []
  if res.stdabbr is Some(a) {
    parts.push("stdabbr=\{@datetime.py_str_repr(a)}")
  }
  if res.stdoffset is Some(o) {
    parts.push("stdoffset=\{o}")
  }
  if res.dstabbr is Some(a) {
    parts.push("dstabbr=\{@datetime.py_str_repr(a)}")
  }
  if res.dstoffset is Some(o) {
    parts.push("dstoffset=\{o}")
  }
  parts.push("start=\{rule_repr(res.start)}")
  parts.push("end=\{rule_repr(res.end)}")
  let unused = if res.any_unused_tokens { "True" } else { "False" }
  "(\{parts.join(", ")}) unused=\{unused}"
}

///|
fn error_kind(e : Error) -> String {
  match e {
    @datetime.ValueError(_) => "raise ValueError"
    @datetime.TypeError(_) => "raise TypeError"
    @datetime.OverflowError(_) => "raise OverflowError"
    _ => "raise \{e}"
  }
}

///|
test "differential: _tzparser and tzstr rules" {
  let bad : Array[String] = []
  for rec in tzparser_corpus {
    let f = rec.split("\u{1f}").map(v => v.to_owned()).collect()
    let s = f[0]
    let parsed = outcome(() => {
      match parse_tzstr(s) {
        None => "None"
        Some(res) => parse_repr(res)
      }
    })
    let made = outcome(() => {
      let z = TzRange::from_tzstr(s, false)
      let parts = [secs_of(z.std_offset), secs_of(z.dst_offset)]
      for y in [2003, 2030] {
        parts.push(
          outcome(() => {
            match z.transitions_checked(y) {
              None => "None"
              Some((a, b)) => "\{a.isoformat()},\{b.isoformat()}"
            }
          }).replace(old="raise ValueError", new="raise"),
        )
      }
      parts.join(" ")
    })
    let got = [s, parsed, made].join("\u{1f}")
    if got != rec {
      bad.push("expected \{rec}\n     got \{got}")
    }
  }
  if bad.length() > 0 {
    fail("\{bad.length()} differ:\n\{bad.join("\n")}")
  }
}

///|
fn secs_of(td : @datetime.TimeDelta) -> String {
  td.total_whole_seconds().to_string()
}

///|
test "tz_tokens matches re.split" {
  inspect(
    tz_tokens("EST+5EDT,M3.2.0/2:30,J60; ñ::").join("|"),
    content="EST|+|5|EDT|,|M|3|.|2|.|0|/|2|:|30|,|J|60|; ñ|:|:",
  )
}
