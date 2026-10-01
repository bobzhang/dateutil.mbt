# tzical port notes

Port of `tz.tzical`, `_tzicalvtz` and `_tzicalvtzcomp` from
`dateutil/tz/tz.py`. It is a separate package because it uses
`rrule.rrulestr`, and `rrule` depends on `parser`, which depends on `tz`.

## API

* `TzIcal::from_string(text, name?)` — Python `tzical(StringIO(text))`;
  `name` stands in for the stream's `name` attribute in `repr()`.
* `TzIcal::from_file(path)` — Python `tzical(filename)` (native and js; on
  the wasm backends it raises `@tz.IOError`).
* `keys()`, `get(tzid?)`, `repr()`; zones are `@datetime.Tz` handles whose
  repr is `<tzicalvtz 'US-Eastern'>`.

## Divergences

* When a datetime precedes every component onset and the zone has no
  STANDARD component, dateutil evaluates `comp[0]` and raises `TypeError`;
  we use the first component.
* `dst()`/`tzname()` with no datetime (a `Time` query) return `None` for
  multi-component zones where dateutil raises `AttributeError`.
* Property names are upper-cased with ASCII rules (Python uses Unicode
  `str.upper()`); offsets accept ASCII digits only.
* Errors raised by `rrulestr` while building a component propagate as-is.

## Tests

`tzical_test.mbt` ports `TZICalTest` (including the shared `TzFoldMixin`
suite in `fold_mixin_test.mbt`, copied from the tz package). Skipped:
`testPickleTzICal` (pickling; also a known failure upstream).
Extra tests cover every parse error message (checked against the
reference) and line unfolding.
