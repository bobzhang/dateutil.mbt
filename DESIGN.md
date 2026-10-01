# dateutil.mbt — design notes

A port of python-dateutil (commit 2642afa, vendored in `.repos/dateutil`) to
MoonBit. Python's `datetime` module does not exist in MoonBit, so the port
ships its own faithful model of it as the foundation package.

## Module / packages

Module name: `bobzhang/dateutil`.

| package          | Python source                        | depends on                    |
|------------------|--------------------------------------|-------------------------------|
| `datetime`       | CPython `datetime`, `calendar`, `time` subset, `dateutil._common.weekday` | core only |
| `easter`         | `dateutil/easter.py`                 | datetime                      |
| `relativedelta`  | `dateutil/relativedelta.py`          | datetime                      |
| `tz`             | `dateutil/tz/{tz,_common,_factories}.py` + `parser._tzparser` (POSIX TZ strings) | datetime, relativedelta, fs (gettz only) |
| `parser`         | `dateutil/parser/{_parser,isoparser}.py` | datetime, tz, relativedelta |
| `rrule`          | `dateutil/rrule.py`                  | datetime, easter, parser (rrulestr), tz |
| `tzical`         | `dateutil/tz/tz.py` `tzical`, `_tzicalvtz` | datetime, tz, rrule (breaks tz→rrule→parser→tz cycle) |
| `utils`          | `dateutil/utils.py`                  | datetime, tz                  |

Out of scope: `tz/win.py` (Windows registry), `zoneinfo` bundled tarball
(no tarball in the vendored tree; gettz reads the system zoneinfo directory
instead), Python-2 compatibility shims, pickling, deprecation warnings.

## `datetime` package (foundation)

Mirrors CPython semantics exactly (proleptic Gregorian, years 1..=9999, ordinal
1 = 0001-01-01, Monday = 0).

```
pub(all) suberror ValueError { ValueError(String) }       // Python ValueError
pub(all) suberror OverflowError { OverflowError(String) } // Python OverflowError

pub struct TimeDelta { days : Int; seconds : Int; microseconds : Int }  // normalized like CPython
  TimeDelta::new(days?, seconds?, microseconds?, milliseconds?, minutes?, hours?, weeks?) -> TimeDelta  // Int args
  TimeDelta::from_seconds(Double) / total_seconds() -> Double / total_microseconds() -> Int64
  Add, Sub, Neg, Eq, Compare, Hash, Show (Python str: "1 day, 2:03:04.000005"), repr()
  mul(Int), abs()

pub struct Date { year; month; day }
  Date::new(y, m, d) raise ValueError, from_ordinal(Int) raise ValueError, to_ordinal,
  weekday, isoweekday, isocalendar, add(TimeDelta) raise OverflowError, sub(Date)->TimeDelta,
  replace(year?, month?, day?) raise ValueError, isoformat, Show/Eq/Compare/Hash, repr(), today()

pub struct Time { hour; minute; second; microsecond; tzinfo : &TzInfo?; fold : Int }

pub struct DateTime { year; month; day; hour; minute; second; microsecond; tzinfo : &TzInfo?; fold : Int }
  DateTime::new(y, m, d, hour?, minute?, second?, microsecond?, tzinfo?, fold?) raise ValueError
  replace(year?, month?, ..., tzinfo? : &TzInfo?, fold?) raise ValueError   // tzinfo=Some(None) => naive
  combine(Date, Time, tzinfo?), date(), time(), timetz()
  add(TimeDelta) -> DateTime raise OverflowError ; sub(TimeDelta) raise OverflowError
  diff(DateTime) -> TimeDelta raise ValueError        // naive/aware mismatch => error (Python TypeError)
  utcoffset(), dst(), tzname()                         // delegate to tzinfo
  astimezone(&TzInfo) raise ValueError, timestamp(), from_timestamp(Double, tz?), utc_from_timestamp
  now(tz?), utcnow(), weekday/isoweekday/to_ordinal/isocalendar
  isoformat(sep?, timespec?), strftime (subset used by dateutil), Show = Python str(), repr()
  equal(DateTime) / compare(DateTime) with CPython aware/naive rules (see below)

pub(open) trait TzInfo : Show {           // Show = Python repr() of the zone
  utcoffset(Self, DateTime) -> TimeDelta?
  dst(Self, DateTime) -> TimeDelta?
  tzname(Self, DateTime) -> String?
  fromutc(Self, DateTime) -> DateTime = _      // default = dateutil `_tzinfo.fromutc` (fold-aware)
  is_ambiguous(Self, DateTime) -> Bool = _     // default = dateutil `_tzinfo.is_ambiguous`
}
```

TzInfo method contract: the `DateTime` argument is interpreted by its wall
fields + `fold`; implementors ignore its `tzinfo` field. `fromutc` receives a
datetime whose wall fields are UTC and returns local wall fields (plus fold);
`DateTime::astimezone` re-attaches the zone box.

Identity: Python compares `dt1.tzinfo is dt2.tzinfo`. We use
`physical_equal` on the `&TzInfo` boxes. A zone converted to `&TzInfo` once and
shared keeps identity (like a Python object); converting the same value twice
yields two "different objects", which only matters for the
same-zone-vs-interzone comparison rule — documented.

Eq/Compare for DateTime follow CPython 3.6+: same tzinfo identity => compare
wall fields (fold ignored); both aware => compare UTC instants (and `==` is
False when either side is in a gap/fold "exception" case per PEP 495); naive vs
aware => `==` false, ordering raises (we panic in `compare`, provide
`try_compare` raising ValueError).

Since MoonBit's `Add` requires same-type operands, datetime ± timedelta are
methods, not operators. TimeDelta has operators.

Calendar helpers (`calendar` module): `is_leap(y)`, `days_in_month(y, m)`,
`monthrange(y, m) -> (first_weekday, ndays)`, `timegm`.

Local time (`time.localtime`, `time.timezone`, `time.altzone`, `time.tzname`,
`time.daylight`): small per-target platform layer — native via a C stub
(`localtime_r`/`tm_gmtoff`/`tm_zone`), js via `Date`, wasm targets fall back to
UTC. Used by `now()` and `tz.tzlocal`.

`Weekday` (from `dateutil._common`): `pub struct Weekday { weekday : Int; n : Int? }`,
constants `MO..SU`, `Weekday::nth(n)` (Python `__call__`), Show `MO`, `MO(+2)`.
Re-exported from relativedelta and rrule.

## Divergences (planned)

* relativedelta fractional arguments (`days=1.5`): Python keeps floats until
  `normalized()`. We take Int fields and expose a `Double` normalizing
  constructor path that pushes fractions into lower units immediately.
* Exceptions: Python's TypeError at the API boundary is mostly made
  impossible by types; ValueError-style failures raise `ValueError` /
  package-specific errors (`ParserError`, ...).
* `tzinfos` callables in the parser become a `(String?, Int?) -> &TzInfo?`
  callback or a `Map[String, TzInfoOrOffset]`.

## Testing

Port the Python test suites (`tests/test_*.py`) package by package as
black-box tests. Additionally build differential corpora by running the
vendored Python implementation (with a local `six` shim) and comparing outputs.

## Revisions after Codex review (round 1)

* **Zone handle.** `pub struct Tz` (datetime pkg) = stable integer identity +
  `&TzInfo` implementation. `DateTime.tzinfo : Tz?`. Python `a is b` ==
  `Tz::is_same`. Zone *value* equality (`tz1 == tz2`) uses the trait method
  `eq_key(Self) -> String?` (a canonical fingerprint, `None` = identity only).
  dateutil constructors that Python caches (tzutc singleton, tzoffset/tzstr
  factories, gettz cache) return the same handle.
* **TzInfo trait** methods take `DateTime?` (`None` for `time` queries) and are
  called with `dt.tzinfo` = the handle that wraps `self`. Trait defaults are
  plain CPython `tzinfo` behavior: `fromutc` = CPython algorithm,
  `is_ambiguous` = `None` (unsupported). dateutil's `_tzinfo` behaviours
  (fold-aware `fromutc`, offset-based `is_ambiguous`) are public helpers that
  dateutil zones opt into. `Tz::fromutc` validates `dt.tzinfo is self`.
* **Time** is a full type (validation, tz queries, compare, isoformat,
  strftime).
* **Errors**: one `pub(all) suberror DateTimeError { ValueError(String);
  OverflowError(String); TypeError(String) }`. TimeDelta operators abort on
  overflow (documented precondition); `checked_*` variants raise.
  DateTime/Date arithmetic raises.
* **Comparison**: `impl Eq` = CPython `__eq__` (never raises; PEP-495
  exception rule). `impl Compare` = CPython ordering, aborts on naive/aware
  mix; `DateTime::checked_compare` raises `TypeError`. `impl Hash` = CPython
  hash (fold-0 utcoffset).
* Extra APIs: `DateTime::from_ordinal`, `timetuple`, `Date::sub_delta`,
  `MINYEAR/MAXYEAR`, calendar helpers valid for any year, Python
  `datetime.timezone` as `Tz::fixed`.
* relativedelta keeps fractional relative fields as `Double` (deferred until
  `normalized()`/application), years/months are `Int`.
* Weekday `n` validation is package-specific (rrule rejects 0).
* parser `tzinfos`: `Map[String, TzInfoSpec]` / callback, where
  `TzInfoSpec` = explicit none | zone | offset seconds | TZ string.
