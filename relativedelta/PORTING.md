# relativedelta — porting notes

Port of `dateutil/relativedelta.py` (python-dateutil 2642afa).

## Representation

```
pub struct RelativeDelta {
  years : Int; months : Int; mut days : Double; leapdays : Int
  hours : Double; minutes : Double; seconds : Double; microseconds : Double
  year : Int?; month : Int?; day : Int?; weekday : Weekday?
  hour : Int?; minute : Int?; second : Int?; microsecond : Int?
}
```

* Python lets `days`/`weeks`/`hours`/`minutes`/`seconds`/`microseconds` be
  floats and keeps them fractional until `normalized()` or application.
  These fields are `Double`, so that behaviour (including `_fix()`'s float
  `divmod`, `normalized()`'s `round(x, n)` cascade and CPython's float
  `timedelta` construction at application time) is reproduced exactly.
  Python ints and integral floats behave identically everywhere except for
  magnitude: values are exact up to 2^53, which is far beyond any
  meaningful date offset.
* `years`/`months` must be integral in Python (`ValueError` otherwise), so
  they are `Int`. `leapdays` is `Int` (only ever an integer in practice).
* The common constructor `RelativeDelta::new` takes `Int` arguments (the
  ergonomic path); `RelativeDelta::from_float` takes `Double` relative
  arguments and raises `ValueError` for fractional `years`/`months`.
* Absolute fields are `Int?` (Python only warns for non-integral absolute
  values; we cannot represent them).
* Repr uses Python's `{:+g}` (exact, correctly rounded) for relative
  fields, so both integer and float cases match Python, including the
  surprising `relativedelta(days=+1.23457e+06)` for large integers.

## API mapping

| Python                                   | MoonBit                                        |
|------------------------------------------|------------------------------------------------|
| `relativedelta(years=1, ...)`            | `RelativeDelta::new(years=1, ...)` (raises on bad `yearday`) |
| `relativedelta(days=1.5, ...)`           | `RelativeDelta::from_float(days=1.5, ...)`     |
| `relativedelta(dt1, dt2)` (datetimes)    | `RelativeDelta::between(dt1, dt2)`             |
| `relativedelta(d1, d2)` (dates)          | `RelativeDelta::between_dates(d1, d2)`         |
| `relativedelta(date, datetime)` (mixed)  | `between(d.to_datetime(), dt)` (Python's coercion) |
| `weekday=MO(-1)` / `weekday=0`           | `weekday=mo.nth(Some(-1))` / `weekday=Weekday::new(0)` |
| `MO`..`SU`                               | `mo`..`su` (re-exported from `@datetime`)      |
| `rd.weeks` / `rd.weeks = n`              | `rd.weeks()` / `rd.set_weeks(n)` (in place)    |
| `rd.normalized()`                        | `rd.normalized()`                              |
| `rd._has_time`                           | `rd.has_time()`                                |
| `rd1 + rd2`, `rd1 - rd2`, `-rd`          | operators `+`, `-`, unary `-`                  |
| `abs(rd)`                                | `rd.abs()`                                     |
| `rd + timedelta`                         | `rd.add_timedelta(td)`                         |
| `rd * f`, `f * rd`, `rd / f`             | `rd.mul(f)`, `rd.div(f)` (`Double`)            |
| `bool(rd)`                               | `rd.to_bool()`                                 |
| `rd1 == rd2`, `hash(rd)`                 | `Eq`, `Hash`                                   |
| `repr(rd)` / `str(rd)`                   | `rd.repr()` / `Show` / `Debug`                 |
| `datetime + rd`, `rd + datetime`         | `rd.add_to_datetime(dt)`                       |
| `datetime - rd`                          | `rd.sub_from_datetime(dt)`                     |
| `date + rd`                              | `rd.add_to_date(d) -> DateOrDateTime`          |
| `date - rd`                              | `rd.sub_from_date(d) -> DateOrDateTime`        |

MoonBit's `Add`/`Sub` need same-typed operands, so applying a delta to a
date/datetime is a method on the delta. Python returns a `date` for
`date + rd` unless `rd._has_time` (some time field set), in which case the
date is first promoted to a naive midnight `datetime`; `add_to_date` returns
`DateOrDateTime` to keep that behaviour (`Date(...)` vs `DateTime(...)`).
As in Python, fractional `days` alone do not promote: `date +
relativedelta(days=1.5)` stays a `Date` (only the whole days of the
resulting `timedelta` count).

## Divergences

* **Errors.** Python `ValueError`/`OverflowError` map to
  `@datetime.ValueError`/`@datetime.OverflowError`. `rd / 0` raises
  `ValueError("float division by zero")` (Python: `ZeroDivisionError`).
  `rd.mul(f)` raises `OverflowError` if `years`/`months` no longer fit an
  `Int` (Python has unbounded ints).
* **Hash.** Python's `__eq__` treats a weekday with `n` in `{None, 0, 1}` as
  equal, but `__hash__` hashes `n` verbatim (so equal deltas can hash
  differently). Our `Hash` is consistent with `Eq`.
* **timedelta at application.** dateutil builds
  `timedelta(days=, hours=, minutes=, seconds=, microseconds=)` from the
  (possibly fractional) fields. We reproduce CPython's C `timedelta`
  constructor (`accum` + half-even rounding of the leftover), which differs
  from the pure-Python `_pydatetime` algorithm (and from
  `@datetime.TimeDelta::from_float`) in the last microsecond for some float
  inputs. The accumulation is done in `Int64` microseconds; sums beyond
  ±9e18 µs (~10^8 days, far outside the date range) raise `OverflowError`
  directly.
* **Type errors.** Python's `TypeError`s for unsupported operand types
  (`rd + 9`, `rd - 14`, `rd == 19`, `relativedelta(dt1='2018-01-01', ...)`)
  are compile-time errors in MoonBit. Aware/naive mixing in `between`
  raises `@datetime.TypeError`.
* **Subclassing.** No inheritance in MoonBit.
* **Python `weekday` int out of range.** `Weekday::new` aborts for values
  outside `0..=6` (Python raises `IndexError`).

## Upstream tests not ported (tests/test_relativedelta.py)

| test | reason |
|------|--------|
| `testInheritance` | no subclassing |
| `testAdditionInvalidType`, `testAdditionUnsupportedType`, `testSubractionWithDatetime`, `testSubtractionInvalidType`, `testSubtractionUnsupportedType`, `testMultiplicationUnsupportedType`, `testDivisionUnsupportedType`, `testInequalityTypeMismatch`, `testInequalityUnsupportedType`, `testRelativeDeltaInvalidDatetimeObject` | operand type errors / `NotImplemented` are prevented statically |
| `testRelativeDeltaFractionalAbsolutes` | checks a `DeprecationWarning` for float absolute fields, which are `Int` here |

`testRightAdditionToDatetime` and `testMultiplication`'s `28 * rd` form map
onto the same methods as their left-hand counterparts.

## Differential tests

`tools/gen_relativedelta_corpus.py` runs the vendored dateutil and writes
`python_corpus_test.mbt` (construction/repr/normalized/weeks/bool, `{:+g}`
formatting, application to edge dates incl. month ends, Feb 29, year 1 and
9999 boundaries, weekday with nth, yearday/nlyearday, leapdays; fractional
fields; `relativedelta(dt1, dt2)` for dates, datetimes, mixed and aware
datetimes; `+ - neg abs * /`, equality/hash with weekday `n` variants).
