# utils — porting notes

Port of `dateutil/utils.py`.

| Python                              | MoonBit                                   |
|-------------------------------------|-------------------------------------------|
| `today(tzinfo=None)`                | `today(tzinfo? : Tz) -> DateTime`         |
| `default_tzinfo(dt, tzinfo)`        | `default_tzinfo(DateTime, Tz) -> DateTime` |
| `within_delta(dt1, dt2, delta)`     | `within_delta(DateTime, DateTime, TimeDelta) -> Bool raise` |

## Divergences

* `within_delta` is typed for `DateTime`s (Python duck-types any values
  supporting `-` and comparison with a `timedelta`, e.g. two `date`s). It
  raises `@datetime.TypeError` for naive/aware mixing and `OverflowError`
  when `-abs(delta)` overflows (e.g. `timedelta.max`), like Python.
* `default_tzinfo` attaches the zone with `DateTime::with_tzinfo` (Python
  `dt.replace(tzinfo=...)`; cannot fail).

## Tests (tests/test_utils.py)

All seven upstream tests are ported, with these adaptations:

* `freezegun` is not available. The three `today` tests
  (`test_utils_today`, `test_utils_today_tz_info`,
  `test_utils_today_tz_info_different_day`) are white-box tests
  (`utils_wbtest.mbt`) of `today_with`, the clock-parameterised core of
  `today`, using a fake `now` that reproduces freezegun's
  `FakeDatetime.now` (including adding `tz_offset` to aware results, which
  is why the last test lands on the next day). A black-box test checks the
  real-clock `today()` for midnight / consistency with `DateTime::now()`.
* `NYC = tz.gettz("America/New_York")` is `@tz.gettz` on native and js
  (`nyc_fs_test.mbt` / `nyc_fs_wbtest.mbt`; needs the system zoneinfo
  database). The wasm backends have no file system, so there
  (`nyc_nofs_*`) the tests use `tzoffset("EST", -18000)`, which is NYC's
  offset on every date the tests use and serves equally as a distinct
  zone object for the `default_tzinfo` identity checks.
