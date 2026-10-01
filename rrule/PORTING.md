# rrule — porting notes

Port of `dateutil/rrule.py` (`rrule`, `rruleset`, `rrulestr`, `weekday`).

## API mapping

| Python | MoonBit |
|---|---|
| `rrule(freq, dtstart=..., ...)` | `Rrule::new(freq, dtstart?, interval?, wkst?, count?, until?, by*?, cache?)` |
| `YEARLY` .. `SECONDLY` | `Freq::Yearly` .. `Freq::Secondly` (`to_int`/`from_int` give the Python ints) |
| `MO`..`SU`, `MO(+1)` | `mo`..`su` (re-exported `@datetime.Weekday`), `nth(mo, 1)` |
| `weekday(wd, n)` | `weekday(wd, n?)` (rejects `n == 0`) |
| `str(rule)` | `Show` (`to_string`) |
| `rule.replace(**kw)` | `Rrule::replace(...)`; nullable fields take `T?` so they can be cleared (`count=None`) |
| `iter(r)` / `list(r)` | `iter()` (lazy `Iter`) / `to_array()` |
| `r[i]`, `r[a:b:c]` | `get(i) -> DateTime?` (`None` = `IndexError`), `slice(start?, stop?, step?)` |
| `dt in r`, `r.count()` | `contains(dt)`, `count()` |
| `before`/`after`/`xafter`/`between` | same names; `xafter` returns a lazy `Iter` |
| `rruleset(cache)` + `rrule/rdate/exrule/exdate` | `RruleSet::new(cache?)` + same method names |
| `rrulestr(s, **kw)` | `rrulestr(s, dtstart?, cache?, unfold?, forceset?, compatible?, ignoretz?, tzids?) -> RruleBase` |
| `rrule` / `rruleset` result of `rrulestr` | `RruleBase::Rule(Rrule)` / `RruleBase::Set(RruleSet)` (same query methods) |
| `tzids` mapping / callable | `TzIds::Mapping(Map)` / `TzIds::Lookup(fn)` |

## Divergences

* **Polymorphic arguments.** Python accepts an int or a sequence for the
  `by*` arguments, and a weekday or an int for `wkst`/`byweekday`. Here the
  `by*` arguments are arrays (pass `[x]`) and weekdays are `Weekday` values
  (`weekdays[i]` for an int). `dtstart`/`until` are `DateTime`; pass
  `Date::to_datetime()` for a Python `date`. An empty array is still
  distinct from an omitted argument, as in Python (`()` vs `None`).
* **`wkst` default** is Monday; Python reads the process-global
  `calendar.firstweekday()`, which has no MoonBit counterpart.
* **Errors during iteration.** Python generators raise lazily. All query
  methods (`to_array`, `count`, `get`, `slice`, `contains`, `before`,
  `after`, `between`) raise `@datetime.DateTimeError`; the lazy
  `iter()`/`xafter()` iterators abort instead (MoonBit `Iter` cannot raise).
  Comparing naive with aware datetimes raises `TypeError` like Python.
* **`IndexError`** raised inside the algorithm (e.g. a `byeaster` offset or
  an nth weekday that indexes past the year masks, or `rrulestr` with only
  a `DTSTART` line) is reported as `ValueError("list index out of range")`;
  `ZeroDivisionError` (`interval=0` with hourly-or-finer frequencies after a
  filtered period) as `ValueError`; the `TypeError` from unpacking `None`
  in `__mod_distance` as `TypeError`.
* **`count` + `until`**: Python only emits a `DeprecationWarning`; there is
  no warnings machinery, so the combination is accepted silently.
* **`between(..., count=1)`**: the unused `count` parameter is not ported.
* **Caching** has no lock (single-threaded), otherwise follows
  `_iter_cached` exactly (shared generator, 10 items per fill).
* **`rrulestr`**:
  * `str.upper()` only maps ASCII letters (non-ASCII input is not
    upper-cased like Python would).
  * `int()` values are limited to the `Int` range.
  * `tzinfos` is not supported yet (TODO(parser)).
  * The callback in `TzIds::Lookup` may raise any error; `rrulestr`
    therefore raises the polymorphic `Error`.
* **Debug/repr**: Python's `repr(rrule)` is the default object repr; our
  `Debug` shows the RFC string.

## Pending dependencies

* `parser.parse` (DTSTART/UNTIL/RDATE/EXDATE values) is a stopgap in
  `deps.mbt` (`parse_datetime`, marked `TODO(parser)`) accepting
  `YYYYMMDD[THHMM[SS]][Z]`.
* `tz.gettz` is the default `tzids` lookup (as in Python). Zone files are
  only available where `tz.gettz` has a file system (native, js), so the
  upstream tests resolving IANA names live in `upstream_gettz_test.mbt`,
  gated to those targets.

## Tests

* `upstream_*_test.mbt` are generated from `tests/test_rrule.py` by
  `tools/gen_rrule_tests.py` (test names `Class.method`);
  `upstream_manual_test.mbt` and `cache_wbtest.mbt` hold hand ports.
* Skipped / adapted upstream tests:
  * `testLongIntegers`, `testToStrLongIntegers`: Python 2 only (`long`).
  * `test_generated_aware_dtstart_rrulestr`: `xfail` upstream (gh #637).
  * `test_generated_aware_dtstart`: upstream freezes the clock
    (`freezegun`); ported as a check against the real clock.
  * `testBadUntilCountRRule`: checks a `DeprecationWarning`; ported as a
    check that the rule is accepted.
  * `testWeekdayEqualitySubclass`: Python duck-typed equality with foreign
    classes; ported as equality with the base `@datetime.Weekday`.
  * `testStrWithTZID*`, `testStrSetExDate*WithTZID`, `testStrUntil*`:
    hand-ported (`upstream_gettz_test.mbt`, native/js only because they
    need the system zoneinfo).
* `corpus_wbtest.mbt` / `corpus_data_wbtest.mbt`: differential corpus from
  the reference implementation (`tools/gen_rrule_corpus.py`): 700 random
  rules over all frequencies and by-rules (first 20 occurrences or the
  error, `str()`, the `rrulestr(str())` round trip, `before`/`after`/
  `between` probes) and 150 random rule sets.
