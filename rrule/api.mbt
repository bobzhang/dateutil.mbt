// The `rrulebase` query API, shared by `Rrule`, `RruleSet` and
// `RruleBase`. Methods that iterate raise `DateTimeError` when the
// underlying Python generator would raise (e.g. invalid rule combinations
// detected during iteration, or comparing naive with aware datetimes);
// `iter`/`xafter` return lazy iterators that abort in that case instead.

///|
/// Python `iter(self)`: a fresh raising generator (honours the cache).
fn Rrule::gen(self : Rrule) -> Gen {
  self.base.iter(() => self.raw_iter())
}

///|
/// Lazily iterate over the occurrences (Python `iter(self)`). Aborts if the
/// underlying generator raises; use `to_array` or the query methods to
/// handle such errors.
pub fn Rrule::iter(self : Rrule) -> Iter[@datetime.DateTime] {
  self.gen().to_iter()
}

///|
/// All occurrences (Python `list(self)`). Does not terminate for unbounded
/// rules.
pub fn Rrule::to_array(
  self : Rrule,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  self.base.to_array(() => self.raw_iter())
}

///|
/// The number of occurrences (Python `count()`); iterates over the whole
/// recurrence unless a previous full iteration recorded it.
pub fn Rrule::count(self : Rrule) -> Int raise @datetime.DateTimeError {
  self.base.count(() => self.raw_iter())
}

///|
/// Python `self[index]`; negative indices count from the end. `None` when
/// the index is out of range (Python `IndexError`).
pub fn Rrule::get(
  self : Rrule,
  index : Int,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  self.base.get(() => self.raw_iter(), index)
}

///|
/// Python `self[start:stop:step]`, including dateutil's quirks: unless the
/// cache is complete or `step < 0`, this is `itertools.islice(self, start
/// or 0, stop or sys.maxsize, step or 1)` (so negative `start`/`stop` raise
/// `ValueError`, and `stop=0` means "no limit").
pub fn Rrule::slice(
  self : Rrule,
  start? : Int,
  stop? : Int,
  step? : Int,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  self.base.slice(() => self.raw_iter(), start, stop, step)
}

///|
/// Python `dt in self`.
pub fn Rrule::contains(
  self : Rrule,
  dt : @datetime.DateTime,
) -> Bool raise @datetime.DateTimeError {
  self.base.contains(() => self.raw_iter(), dt)
}

///|
/// The last occurrence before `dt` (or at `dt` when `inc`).
pub fn Rrule::before(
  self : Rrule,
  dt : @datetime.DateTime,
  inc? : Bool = false,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  self.base.before(() => self.raw_iter(), dt, inc)
}

///|
/// The first occurrence after `dt` (or at `dt` when `inc`).
pub fn Rrule::after(
  self : Rrule,
  dt : @datetime.DateTime,
  inc? : Bool = false,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  self.base.after(() => self.raw_iter(), dt, inc)
}

///|
/// Lazily yield up to `count` occurrences after `dt` (at or after when
/// `inc`); all of them when `count` is omitted. Aborts if the underlying
/// generator raises.
pub fn Rrule::xafter(
  self : Rrule,
  dt : @datetime.DateTime,
  count? : Int,
  inc? : Bool = false,
) -> Iter[@datetime.DateTime] {
  self.base.xafter(() => self.raw_iter(), dt, count, inc).to_iter()
}

///|
/// All occurrences strictly between `after` and `before` (inclusive when
/// `inc`).
pub fn Rrule::between(
  self : Rrule,
  after : @datetime.DateTime,
  before : @datetime.DateTime,
  inc? : Bool = false,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  self.base.between(() => self.raw_iter(), after, before, inc)
}

///|
/// Python `iter(self)`: a fresh raising generator (honours the cache).
fn RruleSet::gen(self : RruleSet) -> Gen {
  self.base.iter(() => self.raw_iter())
}

///|
/// Lazily iterate over the occurrences (Python `iter(self)`). Aborts if the
/// underlying generator raises; use `to_array` or the query methods to
/// handle such errors.
pub fn RruleSet::iter(self : RruleSet) -> Iter[@datetime.DateTime] {
  self.gen().to_iter()
}

///|
/// All occurrences (Python `list(self)`). Does not terminate for unbounded
/// rules.
pub fn RruleSet::to_array(
  self : RruleSet,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  self.base.to_array(() => self.raw_iter())
}

///|
/// The number of occurrences (Python `count()`); iterates over the whole
/// recurrence unless a previous full iteration recorded it.
pub fn RruleSet::count(self : RruleSet) -> Int raise @datetime.DateTimeError {
  self.base.count(() => self.raw_iter())
}

///|
/// Python `self[index]`; negative indices count from the end. `None` when
/// the index is out of range (Python `IndexError`).
pub fn RruleSet::get(
  self : RruleSet,
  index : Int,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  self.base.get(() => self.raw_iter(), index)
}

///|
/// Python `self[start:stop:step]`, including dateutil's quirks: unless the
/// cache is complete or `step < 0`, this is `itertools.islice(self, start
/// or 0, stop or sys.maxsize, step or 1)` (so negative `start`/`stop` raise
/// `ValueError`, and `stop=0` means "no limit").
pub fn RruleSet::slice(
  self : RruleSet,
  start? : Int,
  stop? : Int,
  step? : Int,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  self.base.slice(() => self.raw_iter(), start, stop, step)
}

///|
/// Python `dt in self`.
pub fn RruleSet::contains(
  self : RruleSet,
  dt : @datetime.DateTime,
) -> Bool raise @datetime.DateTimeError {
  self.base.contains(() => self.raw_iter(), dt)
}

///|
/// The last occurrence before `dt` (or at `dt` when `inc`).
pub fn RruleSet::before(
  self : RruleSet,
  dt : @datetime.DateTime,
  inc? : Bool = false,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  self.base.before(() => self.raw_iter(), dt, inc)
}

///|
/// The first occurrence after `dt` (or at `dt` when `inc`).
pub fn RruleSet::after(
  self : RruleSet,
  dt : @datetime.DateTime,
  inc? : Bool = false,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  self.base.after(() => self.raw_iter(), dt, inc)
}

///|
/// Lazily yield up to `count` occurrences after `dt` (at or after when
/// `inc`); all of them when `count` is omitted. Aborts if the underlying
/// generator raises.
pub fn RruleSet::xafter(
  self : RruleSet,
  dt : @datetime.DateTime,
  count? : Int,
  inc? : Bool = false,
) -> Iter[@datetime.DateTime] {
  self.base.xafter(() => self.raw_iter(), dt, count, inc).to_iter()
}

///|
/// All occurrences strictly between `after` and `before` (inclusive when
/// `inc`).
pub fn RruleSet::between(
  self : RruleSet,
  after : @datetime.DateTime,
  before : @datetime.DateTime,
  inc? : Bool = false,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  self.base.between(() => self.raw_iter(), after, before, inc)
}

///|
/// The rule, if this is a `Rule`.
pub fn RruleBase::as_rrule(self : RruleBase) -> Rrule? {
  match self {
    Rule(r) => Some(r)
    Set(_) => None
  }
}

///|
/// The set, if this is a `Set`.
pub fn RruleBase::as_rruleset(self : RruleBase) -> RruleSet? {
  match self {
    Rule(_) => None
    Set(s) => Some(s)
  }
}

///|
/// Lazily iterate over the occurrences (see `Rrule::iter`).
pub fn RruleBase::iter(self : RruleBase) -> Iter[@datetime.DateTime] {
  match self {
    Rule(r) => r.iter()
    Set(s) => s.iter()
  }
}

///|
/// All occurrences (Python `list(self)`).
pub fn RruleBase::to_array(
  self : RruleBase,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.to_array()
    Set(s) => s.to_array()
  }
}

///|
/// The number of occurrences (Python `count()`).
pub fn RruleBase::count(self : RruleBase) -> Int raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.count()
    Set(s) => s.count()
  }
}

///|
/// Python `self[index]` (see `Rrule::get`).
pub fn RruleBase::get(
  self : RruleBase,
  index : Int,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.get(index)
    Set(s) => s.get(index)
  }
}

///|
/// Python `self[start:stop:step]` (see `Rrule::slice`).
pub fn RruleBase::slice(
  self : RruleBase,
  start? : Int,
  stop? : Int,
  step? : Int,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.slice(start?, stop?, step?)
    Set(s) => s.slice(start?, stop?, step?)
  }
}

///|
/// Python `dt in self`.
pub fn RruleBase::contains(
  self : RruleBase,
  dt : @datetime.DateTime,
) -> Bool raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.contains(dt)
    Set(s) => s.contains(dt)
  }
}

///|
/// The last occurrence before `dt` (or at `dt` when `inc`).
pub fn RruleBase::before(
  self : RruleBase,
  dt : @datetime.DateTime,
  inc? : Bool = false,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.before(dt, inc~)
    Set(s) => s.before(dt, inc~)
  }
}

///|
/// The first occurrence after `dt` (or at `dt` when `inc`).
pub fn RruleBase::after(
  self : RruleBase,
  dt : @datetime.DateTime,
  inc? : Bool = false,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.after(dt, inc~)
    Set(s) => s.after(dt, inc~)
  }
}

///|
/// Up to `count` occurrences after `dt` (see `Rrule::xafter`).
pub fn RruleBase::xafter(
  self : RruleBase,
  dt : @datetime.DateTime,
  count? : Int,
  inc? : Bool = false,
) -> Iter[@datetime.DateTime] {
  match self {
    Rule(r) => r.xafter(dt, count?, inc~)
    Set(s) => s.xafter(dt, count?, inc~)
  }
}

///|
/// All occurrences between `after` and `before` (inclusive when `inc`).
pub fn RruleBase::between(
  self : RruleBase,
  after : @datetime.DateTime,
  before : @datetime.DateTime,
  inc? : Bool = false,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  match self {
    Rule(r) => r.between(after, before, inc~)
    Set(s) => s.between(after, before, inc~)
  }
}
