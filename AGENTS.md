# Porting conventions (dateutil.mbt)

This repo ports python-dateutil (vendored, read-only, in `.repos/dateutil`,
gitignored) to MoonBit. Read `DESIGN.md` first — especially the
"Revisions after Codex review" section, which is authoritative.

## Layout

* Module `bobzhang/dateutil`; one package per Python module (see DESIGN.md).
* `datetime/` is our model of CPython's `datetime` (+ `calendar`/`time`
  bits). Explore it with `moon ide doc "@datetime"`; read
  `datetime/pkg.generated.mbti` for the API.
* Every `moon.pkg` starts with `warnings = "-79"`.

## Semantics rules

* Be faithful to dateutil's behaviour, including edge cases. Where MoonBit
  forces a divergence, keep it minimal and record it in `<pkg>/PORTING.md`.
* Zones are `@datetime.Tz` handles (identity = `Tz::is_same`, Python `is`;
  value equality = `==` via `TzInfo::eq_key`). dateutil zones implement
  `@datetime.TzInfo` on a private struct and are exposed as `Tz` handles.
  dateutil `_tzinfo` base-class behaviours live in `tz/common.mbt`
  (`tzinfo_fromutc`, `tzinfo_is_ambiguous`, `enfold`, ...).
* Python `ValueError`/`TypeError`/`OverflowError` → `@datetime.DateTimeError`
  constructors unless Python has a dedicated class (e.g. `ParserError`).
* `Show` = Python `str()`; a `repr()` method = Python `repr()`;
  `impl Debug` returns `Repr(self.repr())` so `assert_eq`/`debug_inspect`
  work. Add `pub extend T with Show::{to_string, output}` (see
  `datetime/extends.mbt`) for public types implementing Show/Compare.
* Python generators → `Iter[T]` (lazy) where reasonable.

## Tests

* Port the upstream test module(s) for your package as black-box tests
  (`<pkg>/<topic>_test.mbt`), keeping upstream test names in the test
  titles so they can be traced. Skip only what cannot apply (Python-2,
  pickling, Windows, warnings machinery…) and list skips with reasons in
  `<pkg>/PORTING.md`.
* Add differential tests generated from the reference implementation where
  it adds coverage. Run the reference with the local shims:
  `. tools/pyenv.sh && python3 -c 'from dateutil import parser; ...'`
  (in a worktree, first `ln -s /Users/hongbozhang/git/dateutil.mbt/.repos .repos`).
  Upstream test modules import fine under the shims, so data tables can be
  extracted programmatically. Commit generator scripts under `tools/`.
* Tests must pass on all backends:
  `moon test --target wasm-gc && moon test --target js && moon test --target native`
  (filesystem/local-time dependent tests may be gated per target via
  `targets` in `moon.pkg`).

## Workflow

* `moon check` often; `moon fmt` and `moon info` before every commit; review
  the `pkg.generated.mbti` diff.
* Commit to your branch in small logical commits.
* Only edit your own package directory (plus new files in `tools/`). If you
  truly need a change elsewhere (e.g. `datetime/`), keep it minimal and
  additive, put it in its own commit prefixed with the package name, and
  call it out in your final report.
* Ask Codex for review/guidance when stuck and once before finishing:
  `codex exec -c model_reasoning_effort=high -s read-only "<question>"`
  (it can read the repo; give it file paths). Address real findings.
