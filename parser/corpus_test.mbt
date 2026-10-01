// Differential corpus (tools/gen_parser_corpus.py): every case is run
// through the MoonBit parser and compared with the reference result.

///|
let ref_info : @parser.ParserInfo = @parser.ParserInfo::new(year=2026)

///|
fn json_str(j : Json) -> String {
  guard j is String(s) else { abort("expected a JSON string") }
  s
}

///|
fn json_int(j : Json) -> Int {
  guard j is Number(n, ..) else { abort("expected a JSON number") }
  n.to_int()
}

///|
fn json_bool(j : Json) -> Bool {
  guard j is (True | False) else { abort("expected a JSON bool") }
  j is True
}

///|
/// Zone names equal to a local zone name take dateutil's `tzlocal()` path,
/// which depends on the machine; the reference ran with local names that
/// never occur in the corpus, so such cases are skipped here. On a machine
/// whose local zone is called "UTC" (e.g. the wasm backends) that includes
/// every result the reference resolved to `tzutc()`, since dateutil renames
/// `Z` and zero offsets to "UTC" first.
fn depends_on_local_zone(s : String, expected : String) -> Bool {
  let (std, dst) = @datetime.local_zone().tzname
  if (std == "UTC" || dst == "UTC") && expected.contains("tzutc()") {
    return true
  }
  @parser.timelex_split(s).iter().any(t => t == std || t == dst)
}

///|
test "differential corpus: parse" {
  let mut n = 0
  let mut skipped = 0
  for line in parse_corpus.split("\n") {
    if line.length() == 0 {
      continue
    }
    guard (try! @json.parse(line))
      is Array([s, Object(o), expected, Array(warned)]) else {
      abort("bad corpus line")
    }
    let s = json_str(s)
    if depends_on_local_zone(s, json_str(expected)) {
      skipped += 1
      continue
    }
    guard o.get("default") is Some(Array(d)) else { abort("no default") }
    let d = d.map(json_int)
    let default = dt(
      d[0],
      d[1],
      d[2],
      hour=d[3],
      minute=d[4],
      second=d[5],
      microsecond=d[6],
    )
    let tzinfos = match o.get("tzinfos") {
      Some(Array(pairs)) =>
        Some(
          offsets(
            pairs.map(p => {
              guard p is Array([name, off]) else { abort("bad tzinfos") }
              (json_str(name), json_int(off))
            }),
          ),
        )
      _ => None
    }
    check_parse(
      s,
      json_str(expected),
      info=ref_info,
      default~,
      ignoretz=o.get("ignoretz").map(json_bool).unwrap_or(false),
      tzinfos?,
      dayfirst?=o.get("dayfirst").map(json_bool),
      yearfirst?=o.get("yearfirst").map(json_bool),
      fuzzy=o.get("fuzzy").map(json_bool).unwrap_or(false),
      tokens=o.get("tokens").map(json_bool).unwrap_or(false),
      warns=warned.map(json_str),
    )
    n += 1
  }
  assert_true(n > 3000)
  assert_true(skipped < 1500)
}

///|
test "differential corpus: isoparser" {
  let mut n = 0
  for line in iso_corpus.split("\n") {
    if line.length() == 0 {
      continue
    }
    guard (try! @json.parse(line)) is Array([meth, s, Object(o), expected]) else {
      abort("bad corpus line")
    }
    let s = json_str(s)
    let expected = json_str(expected)
    let sep = o.get("sep").map(json_str)
    match json_str(meth) {
      "isoparse" =>
        match sep {
          Some(sep) =>
            if expected.has_prefix("ValueError: Separator") {
              check_isoparser_new(sep, expected)
            } else {
              check_isoparse(s, expected, sep~)
            }
          None => check_isoparse(s, expected)
        }
      "parse_isodate" => check_isodate(s, expected, sep?)
      "parse_isotime" => check_isotime(s, expected, sep?)
      "parse_tzstr" =>
        check_tzstr(
          s,
          expected,
          zero_as_utc=o.get("zero_as_utc").map(json_bool).unwrap_or(true),
        )
      _ => abort("unknown method")
    }
    n += 1
  }
  assert_true(n > 1500)
}
