// `rrulebase`: caching and the query API shared by `Rrule` and `RruleSet`.

///|
/// A Python generator: a raising pull function that, once it returns
/// `None` or raises, stays exhausted.
priv struct Gen {
  mut done : Bool
  step : () -> @datetime.DateTime? raise @datetime.DateTimeError
}

///|
fn Gen::new(
  step : () -> @datetime.DateTime? raise @datetime.DateTimeError,
) -> Gen {
  { done: false, step, }
}

///|
/// Python `next(gen)`; `None` = `StopIteration`.
fn Gen::next(self : Gen) -> @datetime.DateTime? raise @datetime.DateTimeError {
  if self.done {
    return None
  }
  errdefer {
    self.done = true
  }
  let r = (self.step)()
  if r is None {
    self.done = true
  }
  r
}

///|
/// Python `iter(list)`: a live iterator over an array.
fn Gen::from_array(xs : Array[@datetime.DateTime]) -> Gen {
  let mut i = 0
  Gen::new(() => {
    if i < xs.length() {
      let v = xs[i]
      i += 1
      Some(v)
    } else {
      None
    }
  })
}

///|
/// Turn a generator into a MoonBit iterator; errors abort.
fn Gen::to_iter(self : Gen) -> Iter[@datetime.DateTime] {
  Iter::new(() => self.next() catch { e => abort(e.to_string()) })
}

///|
/// The mutable cache state of Python's `rrulebase`.
priv struct Base {
  /// `None` when caching is disabled.
  mut cache : Array[@datetime.DateTime]?
  mut cache_complete : Bool
  mut cache_gen : Gen?
  /// Python `_len`: set when a full iteration finishes.
  mut len : Int?
}

///|
fn Base::new(cache : Bool) -> Base {
  {
    cache: if cache {
      Some([])
    } else {
      None
    },
    cache_complete: false,
    cache_gen: None,
    len: None,
  }
}

///|
/// Python `_invalidate_cache`; `fresh` is a new (unstarted) `_iter()`.
fn Base::invalidate(self : Base, fresh : Gen) -> Unit {
  if self.cache is Some(_) {
    self.cache = Some([])
    self.cache_complete = false
    self.cache_gen = Some(fresh)
  }
  self.len = None
}

///|
/// Python `__iter__`; `raw` creates a new `_iter()` generator.
fn Base::iter(self : Base, raw : () -> Gen) -> Gen {
  if self.cache_complete {
    match self.cache {
      Some(c) => Gen::from_array(c)
      None => raw()
    }
  } else if self.cache is None {
    raw()
  } else {
    self.iter_cached()
  }
}

///|
/// Python `_iter_cached`: share one underlying generator between all
/// iterations, filling the cache 10 items at a time.
fn Base::iter_cached(self : Base) -> Gen {
  let mut started = false
  let mut i = 0
  let mut gen : Gen? = None
  let mut cache : Array[@datetime.DateTime] = []
  let mut phase = 0
  Gen::new(fn() -> @datetime.DateTime? raise @datetime.DateTimeError {
    if !started {
      started = true
      gen = self.cache_gen
      cache = self.cache.unwrap_or([])
    }
    if phase == 0 {
      while gen is Some(g) {
        if i == cache.length() {
          if self.cache_complete {
            break
          }
          let mut stopped = false
          for _ in 0..<10 {
            match g.next() {
              Some(x) => cache.push(x)
              None => {
                self.cache_gen = None
                gen = None
                self.cache_complete = true
                stopped = true
                break
              }
            }
          }
          if stopped {
            break
          }
        }
        let v = cache[i]
        i += 1
        return Some(v)
      }
      phase = 1
    }
    match self.len {
      Some(len) if i < len => {
        let v = cache[i]
        i += 1
        Some(v)
      }
      _ => None
    }
  })
}

///|
/// Python `list(self)`.
fn Base::to_array(
  self : Base,
  raw : () -> Gen,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  let g = self.iter(raw)
  let out = []
  while g.next() is Some(x) {
    out.push(x)
  }
  out
}

///|
/// Python `__getitem__(int)`; `None` = `IndexError`.
fn Base::get(
  self : Base,
  raw : () -> Gen,
  item : Int,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  if self.cache_complete && self.cache is Some(c) {
    py_index(c.length(), item).map(i => c[i])
  } else if item >= 0 {
    let g = self.iter(raw)
    let mut res = None
    for _ in 0..<=item {
      match g.next() {
        Some(x) => res = Some(x)
        None => return None
      }
    }
    res
  } else {
    let all = self.to_array(raw)
    py_index(all.length(), item).map(i => all[i])
  }
}

///|
/// Python `__getitem__(slice)`.
fn Base::slice(
  self : Base,
  raw : () -> Gen,
  start : Int?,
  stop : Int?,
  step : Int?,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  if self.cache_complete && self.cache is Some(c) {
    py_slice(c, start, stop, step)
  } else if step is Some(s) && s < 0 {
    py_slice(self.to_array(raw), start, stop, step)
  } else {
    // itertools.islice(self, start or 0, stop or sys.maxsize, step or 1)
    let start = match start {
      None | Some(0) => 0
      Some(s) => s
    }
    let stop = match stop {
      None | Some(0) => None
      Some(s) => Some(s)
    }
    let step = match step {
      None | Some(0) => 1
      Some(s) => s
    }
    if start < 0 || (stop is Some(s) && s < 0) {
      raise @datetime.ValueError(
        "Indices for islice() must be None or an integer: 0 <= x <= sys.maxsize.",
      )
    }
    let g = self.iter(raw)
    let out = []
    // CPython islice_next
    let mut cnt = 0
    let mut next = start
    while true {
      while cnt < next {
        if g.next() is None {
          return out
        }
        cnt += 1
      }
      if stop is Some(s) && cnt >= s {
        return out
      }
      match g.next() {
        None => return out
        Some(x) => {
          cnt += 1
          out.push(x)
          // CPython clamps to `stop` on overflow or overshoot
          let n = next.to_int64() + step.to_int64()
          next = match stop {
            Some(s) if n > s.to_int64() => s
            None if n > 2147483647L => 2147483647
            _ => n.to_int()
          }
        }
      }
    }
    out
  }
}

///|
/// Python `__contains__`.
fn Base::contains(
  self : Base,
  raw : () -> Gen,
  item : @datetime.DateTime,
) -> Bool raise @datetime.DateTimeError {
  if self.cache_complete && self.cache is Some(c) {
    c.contains(item)
  } else {
    let g = self.iter(raw)
    while g.next() is Some(i) {
      if i == item {
        return true
      } else if dt_lt(item, i) {
        return false
      }
    }
    false
  }
}

///|
/// Python `count()`.
fn Base::count(
  self : Base,
  raw : () -> Gen,
) -> Int raise @datetime.DateTimeError {
  if self.len is None {
    let g = self.iter(raw)
    while g.next() is Some(_) {

    }
  }
  // Python returns `self._len`, which a full iteration always sets.
  self.len.unwrap_or(0)
}

///|
/// Python `before(dt, inc)`.
fn Base::before(
  self : Base,
  raw : () -> Gen,
  dt : @datetime.DateTime,
  inc : Bool,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  let g = self.iter(raw)
  let mut last = None
  while g.next() is Some(i) {
    let c = i.checked_compare(dt)
    if (inc && c > 0) || (!inc && c >= 0) {
      break
    }
    last = Some(i)
  }
  last
}

///|
/// Python `after(dt, inc)`.
fn Base::after(
  self : Base,
  raw : () -> Gen,
  dt : @datetime.DateTime,
  inc : Bool,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  let g = self.iter(raw)
  while g.next() is Some(i) {
    let c = i.checked_compare(dt)
    if (inc && c >= 0) || (!inc && c > 0) {
      return Some(i)
    }
  }
  None
}

///|
/// Python `xafter(dt, count, inc)` as a lazy generator.
fn Base::xafter(
  self : Base,
  raw : () -> Gen,
  dt : @datetime.DateTime,
  count : Int?,
  inc : Bool,
) -> Gen {
  let mut g : Gen? = None
  let mut n = 0
  Gen::new(fn() -> @datetime.DateTime? raise @datetime.DateTimeError {
    let gen = match g {
      Some(x) => x
      None => {
        let x = self.iter(raw)
        g = Some(x)
        x
      }
    }
    while gen.next() is Some(d) {
      let c = d.checked_compare(dt)
      if (inc && c >= 0) || (!inc && c > 0) {
        if count is Some(count) {
          n += 1
          if n > count {
            return None
          }
        }
        return Some(d)
      }
    }
    None
  })
}

///|
/// Python `between(after, before, inc)`.
fn Base::between(
  self : Base,
  raw : () -> Gen,
  after : @datetime.DateTime,
  before : @datetime.DateTime,
  inc : Bool,
) -> Array[@datetime.DateTime] raise @datetime.DateTimeError {
  let g = self.iter(raw)
  let mut started = false
  let l = []
  while g.next() is Some(i) {
    let cb = i.checked_compare(before)
    if (inc && cb > 0) || (!inc && cb >= 0) {
      break
    } else if !started {
      let ca = i.checked_compare(after)
      if (inc && ca >= 0) || (!inc && ca > 0) {
        started = true
        l.push(i)
      }
    } else {
      l.push(i)
    }
  }
  l
}
