# tz — porting notes

Port of `dateutil/tz/tz.py`, `tz/_common.py`, `tz/_factories.py` and the
TZ-string parser `parser._tzparser` (which lives here to avoid a
`tz → parser → tz` cycle). `tzical`/`_tzicalvtz` will be a separate
`tzical` package; `tz/win.py` is out of scope.

## API mapping

| Python                                   | MoonBit                                        |
|------------------------------------------|------------------------------------------------|
| `tz.UTC`, `tzutc()`                      | `@tz.utc`, `@tz.tzutc()` (same handle)         |
| `tzoffset(name, seconds/timedelta)`      | `tzoffset(name, seconds)`, `tzoffset_delta(name, td)` (cached) |
| `tzoffset.instance(...)`                 | `tzoffset_instance(name, td)`                  |
| `tzlocal()`                              | `tzlocal()`                                    |
| `tzfile(path)`                           | `tzfile(path)` (native/js)                     |
| `tzfile(fileobj, filename)`              | `tzfile_from_bytes(bytes, filename?)`          |
| `tzrange(...)`                           | `tzrange(stdabbr, stdoffset?, dstabbr?, dstoffset?, start?, end?)` with `TimeDelta` offsets and `@relativedelta.RelativeDelta` rules |
| `tzstr(s, posix_offset)` / `.instance`   | `tzstr(s, posix_offset?)` (cached) / `tzstr_instance` |
| `gettz(name)`                            | `gettz(name?)`                                 |
| `gettz.nocache` / `.cache_clear()` / `.set_cache_size(n)` | `gettz_nocache`, `gettz_cache_clear`, `gettz_set_cache_size` |
| `TZFILES`, `TZPATHS`                     | `tzfiles`, `tzpaths` (mutable arrays)          |
| `datetime_exists`, `datetime_ambiguous`, `resolve_imaginary`, `enfold` | same names |
| `_tzinfo` helpers                        | `tzinfo_fromutc`, `tzinfo_fold_status`, `tzinfo_is_ambiguous`, ... |
| `IOError`/`OSError` from file reads      | `@tz.IOError`                                  |

All zones are `@datetime.Tz` handles. `Tz::is_same` is Python `is`; `==`
follows each class's `__eq__`: `tzutc`/`tzoffset` compare offsets,
`tzfile` compares transition data, `tzrange`/`tzstr` compare
abbreviations, offsets and rules (with `relativedelta.__eq__` semantics),
and `tzlocal` implements its non-transitive `__eq__` (another `tzlocal`
with the same offsets; `tzutc` if it has no DST and is named UTC/GMT with
offset zero; a `tzoffset` with the same name and offset) through
`TzInfo::eq_with`.

## Divergences

* **No weak references.** Python's `gettz`, `tzoffset` and `tzstr`
  factories keep a weak-value dictionary plus a small strong LRU cache.
  Here cached zones are kept until `gettz_cache_clear()` (tzoffset/tzstr
  caches are never cleared, like Python's), i.e. as if the caller still
  held every zone: repeated calls always return the same handle.
  `gettz_set_cache_size` is accepted but has no observable effect.
* **`tzfile` input.** File objects are replaced by `Bytes`
  (`tzfile_from_bytes`) or a path (`tzfile`). Without a file name the
  `repr()` is `tzfile('<bytes>')` (Python would use the stream's `name` or
  `repr()`). Like dateutil only the version-1 (32-bit) data block is used,
  whatever the TZif version. Truncated or inconsistent data (short reads,
  out-of-range type indices, negative counts) raise `ValueError` where
  Python raises `struct.error`/`IndexError`.
* **File system.** `tzfile(path)`/`gettz` read zone files on native and
  js (via `moonbitlang/x/fs`). The wasm backends have no portable file
  system (`@fs` there needs host imports), so there `tzfile(path)` raises
  `IOError` and `gettz` only understands TZ strings, `UTC`/`GMT` and the
  local zone's names. dateutil's bundled zoneinfo tarball and Windows
  zones do not exist here.
* **`gettz` raises** (as Python does) only when an explicit absolute path
  names a file that is not a valid zone file; its type is the generic
  `raise` (`ValueError` or `IOError`).
* **Errors inside tzinfo methods.** `utcoffset`/`dst`/`tzname` cannot
  raise in the `TzInfo` trait. Where Python would raise from them we fall
  back instead: `tzrange` transitions that cannot be computed (an
  `OverflowError` near `datetime.min/max`, a start rule without an end
  rule, an invalid month) mean "no DST"; `tzlocal.is_ambiguous` returns
  `None` when `dt - dst_saved` overflows (so `datetime_ambiguous` uses its
  fold-based fallback); `tzlocal.tzname()` for a `time` (no date) in a zone
  with DST returns `None` (Python fails).
* **`tzoffset` validation.** `tzoffset`/`tzoffset_delta`/`tzoffset_instance`
  reject offsets outside (-24h, 24h) at construction with `ValueError`;
  Python accepts them and fails when the offset is used.
* **`enfold(dt, fold)`** never fails: any non-zero `fold` means 1 (Python's
  `replace(fold=2)` raises `ValueError`).
* **Offsets.** `tzrange` offsets are `TimeDelta`s (Python also accepts
  seconds). Offsets of 24h or more are accepted at construction (as in
  Python) and abort when used (Python raises `ValueError` then).
* **TZ strings.** Python's `int()` accepts non-ASCII digits and arbitrary
  length; the parser here accepts ASCII digit runs of up to 9 digits, and
  offsets/times that do not fit in 32 bits make the string invalid
  (Python builds a zone that fails when used). The deprecated dateutil-specific format
  is parsed but no `DeprecatedTzFormatWarning` is emitted.
* **`datetime_ambiguous`** uses a zone's `is_ambiguous` when it returns
  `Some`; Python additionally swallows any exception raised by a custom
  `is_ambiguous` — here a zone signals "unsupported" with `None`.
* **`resolve_imaginary`** returns `dt` unchanged for existing datetimes;
  Python's "same object" guarantee becomes "equal fields, fold and zone".
* `tzrange.transitions(year)` is not public (zones are opaque handles).
* `tzlocal` uses the C library on native (honouring `TZ` after
  `@datetime.tzset()`), the JS `Date` object on js, and is UTC on wasm.

## Tests

* `tz_test.mbt` — upstream `test_tz.py` (zones that upstream gets from
  `gettz` come from embedded TZif data in `zone_data_test.mbt`, so these
  run on every backend).
* `fold_mixin_test.mbt` — `TzFoldMixin` for tzfile, tzrange and tzstr.
* `gettz_fs_test.mbt` (native, js) — `GettzTest` and friends against the
  system zoneinfo database (`/usr/share/zoneinfo`).
* `tzlocal_native_test.mbt` (native) — `TzLocalNixTest`, `test_tzlocal_*`
  and `TzFoldMixin` with `TZ` set via `@env.set_env_var` + `@datetime.tzset()`.
* `diff_test.mbt` + `diff_corpus_test.mbt`, `diff_corpus_tzlocal_native_test.mbt`
  — differential records from `tools/gen_tz_corpus.py` (UTC→local
  conversions and wall-time queries — utcoffset/dst/tzname/fold,
  is_ambiguous, datetime_exists, datetime_ambiguous, astimezone(UTC),
  resolve_imaginary — around transitions for 27 tzfile zones, 19 tzstr
  strings and tzlocal under 5 POSIX TZ values).
* `tz_wbtest.mbt` + `tzparser_corpus_wbtest.mbt` — `_tzparser` results,
  tzstr offsets and transitions for ~80 valid and invalid TZ strings;
  `testIsStd`, `testLeapCountDecodesProperly`.

Regenerate the data with
`PYTHONPATH=tools/pyshim:.repos/dateutil/src:.repos/dateutil python3 tools/gen_tz_corpus.py && moon fmt`.

### Skipped upstream tests

| Test                                                         | Reason |
|--------------------------------------------------------------|--------|
| `TzWinFoldMixin`, `TzWinTest`, `TzWinLocalTest`              | Windows only (`tz/win.py` not ported) |
| `TzPickleTest`, `TzPickleFileTest`                           | pickling |
| `ZoneInfoGettzTest` (incl. deprecation-warning tests)        | `dateutil.zoneinfo` tarball not ported |
| `TZICalTest`                                                 | `tzical` is a separate package |
| `test_tzoffset_weakref`, `test_tzstr_weakref`, `test_gettz_weakref`, `test_gettz_set_cache_size` | weak references / `gc` (see divergences) |
| `test_tzoffset_sub_minute_rounding`, `test_sub_minute_rounding_tzfile` | Python < 3.6 only |
| `test_gettz_zone_wrong_type`                                 | bytes/non-string names are impossible by types |
| `testInequalityInteger`, `testInequalityUnsupported`, `testInequalityInvalid` (`== 7`), `ComparesEqual` checks | comparing zones with non-zones is impossible by types |
| `TestEnfold.test_fold_replace_exception_duplicate_args`      | Python argument passing |
| `testEqualAmbiguousComparison`                               | skipped upstream ("Known failure") |
| `TZTest.testTZSetDoesntCorrupt`                              | needs the parser; replaced by a tzlocal-follows-TZ check |

`TzLocalTest.testInequalityFixedOffset` depends on the machine's zone
upstream; it runs under a fixed `TZ=JST-9` here. `DatetimeAmbiguousTest`
(Windows-only upstream by an apparent decorator mistake) is ported in
full.
