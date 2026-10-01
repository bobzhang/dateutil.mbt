// Shared helpers for the tz black-box tests.

///|
fn zone_bytes(name : String) -> Bytes {
  guard zone_data.get(name) is Some(b64) else {
    abort("no embedded zone data for \{name}")
  }
  @base64.decode(b64) catch {
    _ => abort("bad base64 for \{name}")
  }
}

///|
let embedded_zones : Map[String, @datetime.Tz] = {}

///|
/// The embedded TZif data for `name` as a `tzfile` (one object per name,
/// like `gettz`'s cache).
fn zone(name : String) -> @datetime.Tz {
  match embedded_zones.get(name) {
    Some(z) => z
    None => {
      let z = @tz.tzfile_from_bytes(zone_bytes(name), filename=name) catch {
        e => abort("cannot load \{name}: \{e}")
      }
      embedded_zones[name] = z
      z
    }
  }
}

///|
fn dt(
  year : Int,
  month : Int,
  day : Int,
  hour? : Int = 0,
  minute? : Int = 0,
  second? : Int = 0,
  tz? : @datetime.Tz,
  fold? : Int = 0,
) -> @datetime.DateTime {
  @datetime.DateTime::new(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    tzinfo?=tz,
    fold~,
  ) catch {
    e => abort(e.to_string())
  }
}

///|
fn hours(h : Int) -> @datetime.TimeDelta {
  @datetime.TimeDelta::new(hours=h)
}

///|
fn seconds(s : Int) -> @datetime.TimeDelta {
  @datetime.TimeDelta::new(seconds=s)
}

///|
/// `(tzname, utcoffset, dst)`, upstream's `get_timezone_tuple`.
fn tz_tuple(
  d : @datetime.DateTime,
) -> (String?, @datetime.TimeDelta?, @datetime.TimeDelta?) {
  (d.tzname(), d.utcoffset(), d.dst())
}

///|
let est_tuple : (String?, @datetime.TimeDelta?, @datetime.TimeDelta?) = (
  Some("EST"),
  Some(@datetime.TimeDelta::new(hours=-5)),
  Some(@datetime.TimeDelta::new(hours=0)),
)

///|
let edt_tuple : (String?, @datetime.TimeDelta?, @datetime.TimeDelta?) = (
  Some("EDT"),
  Some(@datetime.TimeDelta::new(hours=-4)),
  Some(@datetime.TimeDelta::new(hours=1)),
)

///|
/// Parse `YYYY-MM-DDTHH:MM:SS` (naive).
fn iso_dt(s : String) -> @datetime.DateTime {
  let num = (a : Int, b : Int) => {
    let mut v = 0
    for i in a..<b {
      v = v * 10 + (s[i].to_int() - '0'.to_int())
    }
    v
  }
  dt(
    num(0, 4),
    num(5, 7),
    num(8, 10),
    hour=num(11, 13),
    minute=num(14, 16),
    second=num(17, 19),
  )
}

///|
fn iso_naive(d : @datetime.DateTime) -> String {
  d.with_tzinfo(None).isoformat()
}

///|
fn secs_str(td : @datetime.TimeDelta?) -> String {
  match td {
    None => "None"
    Some(t) => t.total_whole_seconds().to_string()
  }
}

///|
fn name_str(s : String?) -> String {
  match s {
    None => "None"
    Some(s) => s
  }
}

///|
fn bool_str(b : Bool) -> String {
  if b {
    "1"
  } else {
    "0"
  }
}

///|
/// Run differential records against `get_zone(key)`; returns mismatches.
fn run_corpus(
  records : Array[String],
  get_zone : (String) -> @datetime.Tz,
) -> Array[String] raise {
  let bad : Array[String] = []
  for rec in records {
    let f = rec.split("|").map(v => v.to_owned()).collect()
    let z = get_zone(f[1])
    let got = if f[0] == "F" {
      let u = iso_dt(f[2]).with_tzinfo(Some(@tz.utc))
      let loc = u.astimezone(tz=z)
      [
        "F",
        f[1],
        f[2],
        iso_naive(loc),
        loc.fold.to_string(),
        secs_str(loc.utcoffset()),
        secs_str(loc.dst()),
        name_str(loc.tzname()),
      ]
    } else {
      let fold = if f[3] == "1" { 1 } else { 0 }
      let d = iso_dt(f[2]).with_tzinfo(Some(z)).with_fold(fold)
      let amb = z.is_ambiguous(d).unwrap()
      let back = d.astimezone(tz=@tz.utc)
      let res = @tz.resolve_imaginary(d)
      [
        "W",
        f[1],
        f[2],
        f[3],
        secs_str(d.utcoffset()),
        secs_str(d.dst()),
        name_str(d.tzname()),
        bool_str(amb),
        bool_str(@tz.datetime_exists(d)),
        bool_str(@tz.datetime_ambiguous(d)),
        iso_naive(back),
        "\{iso_naive(res)}/\{res.fold}",
      ]
    }
    let got = got.join("|")
    if got != rec {
      bad.push("expected \{rec}\n     got \{got}")
    }
  }
  bad
}

///|
fn check_corpus(
  records : Array[String],
  get_zone : (String) -> @datetime.Tz,
) -> Unit raise {
  let bad = run_corpus(records, get_zone)
  if bad.length() > 0 {
    let shown = bad[0:if bad.length() < 20 { bad.length() } else { 20 }]
    fail(
      "\{bad.length()} of \{records.length()} records differ:\n\{shown.join("\n")}",
    )
  }
}

///|
/// `relativedelta(...)` for tzrange rules.
fn rd(
  days? : Int = 0,
  hours? : Int = 0,
  seconds? : Int = 0,
  month? : Int,
  day? : Int,
  weekday? : @datetime.Weekday,
  hour? : Int,
) -> @tz.TzRangeDelta {
  @tz.TzRangeDelta::new(days~, hours~, seconds~, month?, day?, weekday?, hour?) catch {
    e => abort(e.to_string())
  }
}
