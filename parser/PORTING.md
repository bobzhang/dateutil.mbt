# parser — porting notes

Ports `dateutil/parser/_parser.py` (`_timelex`, `_resultbase`/`_result`,
`parserinfo`, `_ymd`, `parser`, `parse`, `ParserError`,
`UnknownTimezoneWarning`) and `dateutil/parser/isoparser.py`. The POSIX TZ
string parser (`_tzparser`/`_parsetz`) lives in the `tz` package.

## API mapping

| Python | MoonBit |
|---|---|
| `parse(timestr, parserinfo=None, **kw)` | `parse(timestr, parserinfo?, default?, ignoretz?, tzinfos?, dayfirst?, yearfirst?, fuzzy?, on_warning?)` |
| `parse(..., fuzzy_with_tokens=True)` → `(dt, tokens)` | `parse_with_tokens(...)` → `(DateTime, Array[String])` |
| `parser(info)` / `parser.parse` | `Parser::new(info?)` / `Parser::parse`, `Parser::parse_with_tokens` |
| `parserinfo` subclass (`JUMP`, `WEEKDAYS`, `MONTHS`, `HMS`, `AMPM`, `UTCZONE`, `PERTAIN`, `TZOFFSET`) | `ParserInfo::new(jump?, weekdays?, months?, hms?, ampm?, utczone?, pertain?, tzoffset?)`; defaults are `default_jump`, `default_months`, ... |
| overriding `parserinfo.convertyear` | `ParserInfo::new(convertyear=(info, year, century_specified) => ...)`; `ParserInfo::default_convertyear` is `super().convertyear` |
| `parserinfo._year` / `_century` | `ParserInfo::new(year?)` (default: current local year); fields `year`, `century` |
| `parserinfo.jump/weekday/month/hms/ampm/pertain/utczone/tzoffset/convertyear` | methods of the same names |
| `tzinfos` dict / callable | `TzInfos::Table(Map[String, TzInfoSpec])` / `TzInfos::Callback((String?, Int?) -> TzInfoSpec raise)` |
| `tzinfos` values `None` / tzinfo / int / str | `TzInfoSpec::NoTz` / `Zone(Tz)` / `Offset(Int)` / `TzString(String)` |
| `ParserError(fmt, arg)` (`str`, `repr`, `.args`) | `ParserError(String, String)`; `Show` = `str`, `repr()` |
| `UnknownTimezoneWarning` via `warnings.warn` | `on_warning? : (UnknownTimezoneWarning) -> Unit` callback (ignored when absent); `Show` gives the Python message |
| `_timelex.split(s)` | `timelex_split(s)` |
| `isoparser(sep=None)` | `IsoParser::new(sep? : String)` (raises `ValueError`) |
| `isoparser.isoparse/parse_isodate/parse_isotime/parse_tzstr` | `IsoParser::isoparse/parse_isodate/parse_isotime/parse_tzstr(zero_as_utc?)` |
| `isoparse(s)` | `isoparse(s)` |

`parse` raises `ParserError` (Python `ParserError`), `@datetime.OverflowError`
(Python `OverflowError` from `datetime.replace` / date arithmetic) or the
`@datetime.DateTimeError` raised by zone constructors (e.g. `tzoffset`), so
it is declared with a plain `raise`. The isoparser raises
`@datetime.DateTimeError` (`ValueError`, `OverflowError`) like Python.

## Faithfulness notes

* Python `str` semantics are reproduced with generated Unicode tables
  (`tools/gen_parser_unicode.py`, Python 3.13 / Unicode 15.1): the tokenizer
  uses `str.isalpha`/`isdigit`/`isspace`, word lookups use `str.lower()`
  (including `İ` → `i̇` and CPython's final-sigma context rule, with Cased /
  Case_Ignorable tables derived from `str.lower()`), and `int()`, `float()`
  and `Decimal()` accept Unicode decimal digits and `_` separators. `int()`
  of a string with more than 4300 digits fails like CPython's default
  `sys.get_int_max_str_digits()`. Lengths and slices are by code point.
* Numeric tokens are decimals (`Decimal` in Python). `value % 1` and
  `60 * (value % 1)` follow the default decimal context: results are
  rounded to 28 significant digits (ROUND_HALF_EVEN), and `% 1` of a value
  whose integer part has more than 28 digits fails with DivisionImpossible.
* Parsed integers are kept as `Int64` and saturate at 10**18; a value that
  does not fit a C `int` raises `OverflowError("Python int too large to
  convert to C int")` when it reaches `datetime.replace`, like CPython.
  Saturation only changes error messages for absurdly long digit strings
  (except as noted below for hooks and callbacks).
* Two-digit years: the default `ParserInfo` takes the current local year
  when it is created (Python: when `parserinfo()` is created; dateutil's
  `DEFAULTPARSER` at import time, ours on first use).

## Divergences

* Input must be a `String`: Python also accepts `bytes`, `bytearray` and
  character streams (decode them first). `TypeError` for other inputs and
  for invalid `tzinfos` values is prevented by the types.
* `tzinfos` tables are keyed by `String`; Python dicts could contain a
  `None` key.
* `tzoffset` with an offset of 24 hours or more: dateutil builds the zone
  (the datetime is unusable — CPython raises on `utcoffset()`); the MoonBit
  `tz.tzoffset` validates on construction, so e.g. `parse("10:00 +2500")`
  raises `ValueError` (the differential corpus encodes this).
* `ParserInfo` hooks: only `convertyear` is overridable as a function; the
  other lookups are customised through the tables. `parserinfo.validate`
  cannot be overridden. The `convertyear` hook takes and returns `Int`;
  years that do not fit an `Int` (more than 10 digits) bypass the hook
  (the default rule leaves them unchanged and they then overflow).
* `tzinfos` callbacks receive the offset as `Int?`; an offset that does not
  fit an `Int` (e.g. `"+999999:00"`) raises `OverflowError` instead of being
  passed on as a big integer.
* `decimal.InvalidOperation` (Python raises it out of `parse` for `% 1` of a
  number with more than 28 integer digits followed by `h`/`m`/`:`) is
  reported as `ValueError("[<class 'decimal.DivisionImpossible'>]")`.
* A custom `weekdays` table with more than 7 entries: Python raises
  `IndexError` from `relativedelta(weekday=7)`; we raise
  `ValueError("tuple index out of range")`, which `parse` reports as
  `ParserError`.
* `IsoParser::new` takes the separator as a `String` (so Python's length and
  ASCII checks still apply); Python's `bytes` separator is not supported.
* Local zone names (`time.tzname`) come from `@datetime.local_zone()`,
  which honours `TZ` (after `@datetime.tzset()`) on every backend; e.g.
  with `TZ=Europe/London`, `BST` parses as `tzlocal()` (+01:00 in summer).
  On a machine (or wasm host) whose zone resolves to UTC — exactly like
  Python there — `Z`, `UTC` and zero offsets resolve to `tzlocal()`. Only
  js without a file system (browsers) uses the host `Date`, whose `Intl`
  names (`GMT+1`) are not real abbreviations.

## Dependencies

`tz.tzstr` (for `TzInfoSpec::TzString`), `tz.tzlocal` (zone names found in
`time.tzname`), `tz.enfold`, `tz.tzoffset`/`tz.utc` and
`relativedelta(weekday=...)` come from the `tz` and `relativedelta`
packages. Tests needing `tz.gettz` (`test_parse_tzinfos_fold`, the `gettz`
zones of `test_isoparse_prop`) live in `gettz_test.mbt`, which reads the
system zoneinfo (on every backend) and is skipped silently if the zones
are missing.

## Tests

* `upstream_generated_test.mbt` — generated by
  `tools/gen_parser_upstream_tests.py`, which runs every test (and
  parametrization, xfail tests included) of upstream `tests/test_parser.py`
  and `tests/test_isoparser.py` against the vendored reference and records
  each `parse`/`isoparse`/`isoparser` call with the reference result.
* `tz_deps_test.mbt`, `gettz_test.mbt` — upstream tests using `tzstr`,
  `tzlocal` and `gettz` zones.
* `localtime_env_test.mbt` — `TestTZVar::*` (every backend: `TZ` is set
  with `@env.set_env_var` + `@datetime.tzset()`) and local zone names under
  `TZ=Europe/London` (`BST`) and a southern-hemisphere POSIX TZ string.
* `parser_test.mbt` — hand ports of the tests the generator cannot express
  (custom `parserinfo` subclasses, zone objects/callables in `tzinfos`,
  byte inputs, `ParserError` repr, warnings).
* `internals_wbtest.mbt` — `tests/test_internals.py::test_YMD_could_be_day`.
* `property_test.mbt` — `tests/property/test_parser_prop.py` and
  `test_isoparse_prop.py` as deterministic sweeps.
* `corpus_test.mbt` / `corpus_data_test.mbt` — differential corpus from
  `tools/gen_parser_corpus.py` (strftime formats, token soups, fuzzy
  sentences, edge cases, every option combination; isoparser inputs and
  mutations). Cases whose result depends on the machine's local zone names
  are skipped at run time.

### Skipped upstream tests

| Test | Reason |
|---|---|
| `TestInputTypes::test_none_invalid`, `test_int_invalid` | `TypeError` for non-string input is prevented by the types |
| `TestInputTypes::test_duck_typing`, `test_parse_stream` | stream inputs are not supported (String only) |
| `TestInputTypes::test_parse_bytes`, `test_parse_bytearray`, `test_parse_str`, `ParserTest::testParserParseStr` | adapted: the bytes are decoded with `@utf8.decode` first |
| `TestTzinfoInputTypes::test_invalid_tzinfo_input` | invalid `tzinfos` values are prevented by the types |
| `ParserTest::testDateCommandFormatWithLong` | Python 2 only (`long`) |
| `TestParseUnimplementedCases::test_somewhat_ambiguous_string` | xfail upstream; fails on `self.tzinfos` before calling `parse` |
| `test_isoparser::test_isoparser_byte_sep` | `bytes` separator (xfail on Python 3) |
| `test_internals::test_parser_private_warns`, `test_parser_parser_private_not_warns` | deprecation-warning machinery for private names |
| `test_internals::test_tzstr_internal_timedeltas` | belongs to the `tz` package |
