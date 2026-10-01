# dateutil.mbt

A MoonBit port of [python-dateutil](https://github.com/dateutil/dateutil)
(ported from upstream commit `2642afa`), together with a faithful model of
CPython's `datetime` module that it is built on. It runs on the wasm,
wasm-gc, js and native backends.

| package | Python module | what it does |
|---|---|---|
| `@datetime` | `datetime`, bits of `calendar`/`time` | `DateTime`, `Date`, `Time`, `TimeDelta`, the `TzInfo` protocol and `Tz` zone handles, PEP 495 folds, `strftime`, local time |
| `@relativedelta` | `dateutil.relativedelta` | calendar-aware deltas (`months=+1`, `weekday=FR(-1)`, …) |
| `@rrule` | `dateutil.rrule` | RFC 5545 recurrence rules, rule sets and `rrulestr` |
| `@parser` | `dateutil.parser` | the generic `parse()` and the strict ISO-8601 `isoparse()` |
| `@tz` | `dateutil.tz` | `tzutc`, `tzoffset`, `tzlocal`, `tzfile`, `tzrange`, `tzstr`, `gettz`, fold/gap helpers |
| `@tzical` | `dateutil.tz.tzical` | time zones from iCalendar `VTIMEZONE` blocks |
| `@easter` | `dateutil.easter` | Western, Orthodox and Julian Easter |
| `@utils` | `dateutil.utils` | `today`, `default_tzinfo`, `within_delta` |

Behaviour follows dateutil (and CPython's `datetime`) closely, including
edge cases; the upstream test suites are ported and complemented by large
differential corpora generated from the Python reference. Deliberate
divergences are listed in each package's `PORTING.md`; the overall design
is described in [DESIGN.md](DESIGN.md).

## Quick tour

### Parsing

```mbt check
///|
test "parse" {
  let default = @datetime.DateTime::new(2003, 9, 25)
  inspect(
    @parser.parse(
      "Thu Sep 25 10:36:28 BRST 2003",
      default~,
      tzinfos=Table({ "BRST": Offset(-10800) }),
    ),
    content="2003-09-25 10:36:28-03:00",
  )
  inspect(@parser.parse("10:36", default~), content="2003-09-25 10:36:00")
  inspect(
    @parser.parse("Sep 03", default~, dayfirst=true),
    content="2003-09-03 00:00:00",
  )
  let (dt, skipped) = @parser.parse_with_tokens(
    "Today is 25 of September of 2003, exactly at 10:49:41 with timezone -03:00.",
    default~,
  )
  inspect(dt, content="2003-09-25 10:49:41-03:00")
  debug_inspect(
    skipped,
    content=(
      #|["Today is ", "of ", ", exactly at ", " with timezone ", "."]
    ),
  )
  inspect(
    @parser.isoparse("2018-W01-3T14:30:00.25+05:30"),
    content="2018-01-03 14:30:00.250000+05:30",
  )
}
```

### Relative deltas

```mbt check
///|
test "relativedelta" {
  let now = @datetime.DateTime::new(2003, 9, 17, hour=20, minute=54, second=47)
  // next month, plus one week, at 10am
  inspect(
    @relativedelta.RelativeDelta::new(months=1, weeks=1, hour=10).add_to_datetime(
      now,
    ),
    content="2003-10-24 10:54:47",
  )
  // month arithmetic clamps to the end of the month
  inspect(
    @relativedelta.RelativeDelta::new(months=1).add_to_date(
      @datetime.Date::new(2003, 1, 31),
    ),
    content="2003-02-28",
  )
  // the last Friday of the month
  inspect(
    @relativedelta.RelativeDelta::new(
      day=31,
      weekday=@relativedelta.fr.nth(Some(-1)),
    ).add_to_datetime(now),
    content="2003-09-26 20:54:47",
  )
  // the difference between two dates, in calendar terms
  inspect(
    @relativedelta.RelativeDelta::between_dates(
      @datetime.Date::new(2003, 9, 17),
      @datetime.Date::new(1978, 4, 5),
    ),
    content="relativedelta(years=+25, months=+5, days=+12)",
  )
}
```

### Recurrence rules

```mbt check
///|
test "rrule" {
  let start = @datetime.DateTime::new(1997, 9, 2, hour=9)
  // every other week on Tuesday and Thursday, 6 occurrences
  let rule = @rrule.Rrule::new(Weekly, dtstart=start, interval=2, count=6, byweekday=[
    @rrule.tu, @rrule.th,
  ])
  inspect(
    rule.to_array().map(d => d.to_string()).join("\n"),
    content=(
      #|1997-09-02 09:00:00
      #|1997-09-04 09:00:00
      #|1997-09-16 09:00:00
      #|1997-09-18 09:00:00
      #|1997-09-30 09:00:00
      #|1997-10-02 09:00:00
    ),
  )
  inspect(
    rule,
    content=(
      #|DTSTART:19970902T090000
      #|RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=6;BYDAY=TU,TH
    ),
  )
  // parse RFC 5545 text; the last Friday-the-13th before 2030
  let fridays = @rrule.rrulestr(
    "DTSTART:20000101T000000\nRRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13",
  )
  inspect(
    fridays.before(@datetime.DateTime::new(2030, 1, 1)).unwrap(),
    content="2029-07-13 00:00:00",
  )
}
```

### Time zones

```mbt check
///|
test "tz" {
  // POSIX TZ strings work everywhere; gettz also reads the system
  // zoneinfo database (on wasm through MoonBit's host file-system imports).
  let eastern = @tz.tzstr("EST5EDT,M3.2.0,M11.1.0")
  let summer = @datetime.DateTime::new(2021, 7, 4, hour=12, tzinfo=eastern)
  inspect(summer, content="2021-07-04 12:00:00-04:00")
  inspect(summer.astimezone(tz=@tz.utc), content="2021-07-04 16:00:00+00:00")
  // PEP 495 folds: 1:30 happens twice on 2021-11-07
  let ambiguous = @datetime.DateTime::new(
    2021,
    11,
    7,
    hour=1,
    minute=30,
    tzinfo=eastern,
  )
  inspect(@tz.datetime_ambiguous(ambiguous), content="true")
  debug_inspect(ambiguous.tzname(), content="Some(\"EDT\")")
  debug_inspect(@tz.enfold(ambiguous).tzname(), content="Some(\"EST\")")
  // and 2:30 on 2021-03-14 never happens
  let imaginary = @datetime.DateTime::new(
    2021,
    3,
    14,
    hour=2,
    minute=30,
    tzinfo=eastern,
  )
  inspect(@tz.datetime_exists(imaginary), content="false")
  inspect(@tz.resolve_imaginary(imaginary), content="2021-03-14 03:30:00-04:00")
  // fixed offsets are cached like in dateutil
  let brst = @tz.tzoffset(Some("BRST"), -10800)
  assert_true(brst.is_same(@tz.tzoffset(Some("BRST"), -10800)))
  inspect(brst, content="tzoffset('BRST', -10800)")
}
```

### iCalendar time zones

```mbt check
///|
test "tzical" {
  let ical = @tzical.TzIcal::from_string(
    (
      #|BEGIN:VTIMEZONE
      #|TZID:US-Pacific
      #|BEGIN:STANDARD
      #|DTSTART:19671029T020000
      #|RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10
      #|TZOFFSETFROM:-0700
      #|TZOFFSETTO:-0800
      #|TZNAME:PST
      #|END:STANDARD
      #|BEGIN:DAYLIGHT
      #|DTSTART:19870405T020000
      #|RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=4
      #|TZOFFSETFROM:-0800
      #|TZOFFSETTO:-0700
      #|TZNAME:PDT
      #|END:DAYLIGHT
      #|END:VTIMEZONE
    ),
  )
  let pacific = ical.get(tzid="US-Pacific").unwrap()
  inspect(
    @datetime.DateTime::new(2003, 7, 1, tzinfo=pacific),
    content="2003-07-01 00:00:00-07:00",
  )
}
```

### Utilities

```mbt check
///|
test "utils" {
  let est = @tz.tzoffset(Some("EST"), -18000)
  let naive = @datetime.DateTime::new(2014, 1, 1, hour=12, minute=30)
  inspect(
    @utils.default_tzinfo(naive, est),
    content="2014-01-01 12:30:00-05:00",
  )
  inspect(
    @utils.within_delta(
      naive,
      naive.add(@datetime.TimeDelta::new(milliseconds=3)),
      @datetime.TimeDelta::new(seconds=1),
    ),
    content="true",
  )
}
```

### Easter

```mbt check
///|
test "easter" {
  inspect(@easter.easter(2024), content="2024-03-31")
  inspect(@easter.easter(2024, variant=Orthodox), content="2024-05-05")
}
```

## Notable differences from Python

* MoonBit operators need operands of the same type, so `datetime +
  timedelta` is `dt.add(td)`, `datetime - datetime` is `dt.diff(other)`,
  and `dt + relativedelta` is `rd.add_to_datetime(dt)`.
* Time zones are `@datetime.Tz` handles. `a.is_same(b)` is Python's `a is
  b` (which drives same-zone comparison semantics), `a == b` is zone
  equality.
* Python exceptions map to `@datetime.DateTimeError` (`ValueError`,
  `OverflowError`, `TypeError`) or package errors such as
  `@parser.ParserError` and `@tz.IOError`.
* There are no weak references or warnings: zone caches hold strong
  references and parser warnings go to an optional callback.
* System local time (`DateTime::now()`, `timestamp()`, `astimezone()`,
  `tz.tzlocal()`, local zone names in the parser) uses the C library on
  native. On wasm, wasm-gc and js it is computed in MoonBit with glibc's
  rules: `TZ` (a zone name, a TZif path or a POSIX TZ string; empty means
  UTC) or else `/etc/localtime`, read from the system zoneinfo database
  (TZif v1-v4, including the footer rule after the last transition);
  anything unresolvable is UTC. This needs file access: on wasm the host
  must provide MoonBit's `__moonbit_fs_unstable`/env imports (as `moon run`
  and `moon test` do), on js Node's `process.getBuiltinModule` (Node >=
  22.3, Deno, Bun). In a browser, unless `TZ` is a POSIX string, local time
  falls back to the JS `Date` object, which is approximate (`isdst` from a
  January/July comparison, `Intl` names such as `GMT+1` instead of `BST`).
  `gettz` and `tzfile(path)` read files the same way.

## Development

```bash
moon test --target all
```

The `tools/` directory holds the generators of the differential test
corpora. They run the vendored python-dateutil (clone it into
`.repos/dateutil`) with small local shims for `six`, `pytest` and
`freezegun`: `. tools/pyenv.sh && python3 tools/gen_rrule_corpus.py`.

## License

Apache-2.0 for this port. python-dateutil is dual-licensed under the
Apache-2.0 and BSD-3-Clause licenses; see [LICENSE-dateutil](LICENSE-dateutil).
