// `rrule._iter`: the recurrence generator, as a resumable state machine.
// Each "period" (year/month/week/day/hour/... depending on `freq`) is
// filtered into a list of kept days; candidates (day x time) are then built
// and checked against `until`/`dtstart`/`count` one at a time, exactly like
// the Python generator's inner loops (with `bysetpos`, the period's
// candidates are built eagerly, as in Python).

///|
priv struct RruleGen {
  rr : Rrule
  ii : IterInfo
  mut year : Int
  mut month : Int
  mut day : Int
  mut hour : Int
  mut minute : Int
  mut second : Int
  mut weekday : Int
  /// Current timeset as `(h, m, s)` triples.
  mut timeset : Array[(Int, Int, Int)]
  mut total : Int
  mut count : Int?
  /// `bysetpos` candidates of the current period (eagerly built).
  buf : Array[@datetime.DateTime]
  mut pos : Int
  /// Without `bysetpos`: position in `kept` x `timeset`.
  mut day_pos : Int
  mut time_pos : Int
  /// `false` until the first period has been expanded.
  mut started : Bool
  /// Whether some day of the current period was filtered out.
  mut filtered : Bool
  /// Kept day indices of the current period (scratch).
  kept : Array[Int]
}

///|
/// A fresh, unstarted `_iter()` generator.
fn Rrule::raw_iter(self : Rrule) -> Gen {
  let mut state : RruleGen? = None
  Gen::new(fn() -> @datetime.DateTime? raise @datetime.DateTimeError {
    let g = match state {
      Some(g) => g
      None => {
        let g = RruleGen::init(self)
        state = Some(g)
        g
      }
    }
    g.next()
  })
}

///|
fn RruleGen::init(rr : Rrule) -> RruleGen raise @datetime.DateTimeError {
  let d = rr.dtstart
  let ii = IterInfo::new(rr)
  ii.rebuild(d.year, d.month)
  let g : RruleGen = {
    rr,
    ii,
    year: d.year,
    month: d.month,
    day: d.day,
    hour: d.hour,
    minute: d.minute,
    second: d.second,
    weekday: d.weekday(),
    timeset: [],
    total: 0,
    count: rr.count,
    buf: [],
    pos: 0,
    day_pos: 0,
    time_pos: 0,
    started: false,
    filtered: false,
    kept: [],
  }
  if rr.freq < Hourly {
    g.timeset = rr.timeset
  } else {
    let t = rr.tables
    if (rr.byhour is Some(bh) && !bh.is_empty() && !in_table(t.byhour, g.hour)) ||
      (
        rr.freq >= Minutely &&
        rr.byminute is Some(bm) &&
        !bm.is_empty() &&
        !in_table(t.byminute, g.minute)
      ) ||
      (
        rr.freq >= Secondly &&
        rr.bysecond is Some(bs) &&
        !bs.is_empty() &&
        !in_table(t.bysecond, g.second)
      ) {
      g.timeset = []
    } else {
      g.timeset = g.gettimeset()
    }
  }
  g
}

///|
/// Python `htimeset` / `mtimeset` / `stimeset` for the current time.
fn RruleGen::gettimeset(
  self : RruleGen,
) -> Array[(Int, Int, Int)] raise @datetime.DateTimeError {
  let rr = self.rr
  let tset = []
  match rr.freq {
    Hourly =>
      for m in rr.byminute.unwrap_or([]) {
        for s in rr.bysecond.unwrap_or([]) {
          check_time(self.hour, m, s)
          tset.push((self.hour, m, s))
        }
      }
    Minutely =>
      for s in rr.bysecond.unwrap_or([]) {
        check_time(self.hour, self.minute, s)
        tset.push((self.hour, self.minute, s))
      }
    _ => {
      check_time(self.hour, self.minute, self.second)
      tset.push((self.hour, self.minute, self.second))
    }
  }
  tset.sort()
  tset
}

///|
/// Record the final length (Python `self._len = total`) and stop.
fn RruleGen::finish(self : RruleGen) -> @datetime.DateTime? {
  self.rr.base.len = Some(self.total)
  self.pos = self.buf.length()
  self.day_pos = self.kept.length()
  None
}

///|
fn RruleGen::next(
  self : RruleGen,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  let rr = self.rr
  for ;; {
    while self.next_candidate() is Some(res) {
      if rr.until is Some(until) && res.checked_compare(until) > 0 {
        return self.finish()
      } else if res.checked_compare(rr.dtstart) >= 0 {
        if self.count is Some(c) {
          // Python: count -= 1; if count < 0: return
          if c <= 0 {
            return self.finish()
          }
          self.count = Some(c - 1)
        }
        self.total += 1
        return Some(res)
      }
    }
    if self.started {
      if !self.advance() {
        return self.finish()
      }
    }
    self.started = true
    self.expand()
  }
}

///|
/// The next candidate of the current period, if any.
fn RruleGen::next_candidate(
  self : RruleGen,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  if self.pos < self.buf.length() {
    let res = self.buf[self.pos]
    self.pos += 1
    return Some(res)
  }
  let kept = self.kept
  let timeset = self.timeset
  while self.day_pos < kept.length() {
    let i = kept[self.day_pos]
    if self.time_pos == 0 &&
      i >= self.ii.yearlen &&
      self.year + 1 > @datetime.MAXYEAR {
      // Python computes `date.fromordinal(...)` per day, even for an empty
      // timeset
      raise @datetime.ValueError("year \{self.year + 1} is out of range")
    }
    if self.time_pos < timeset.length() {
      let t = timeset[self.time_pos]
      self.time_pos += 1
      return Some(self.make(i, t))
    }
    self.day_pos += 1
    self.time_pos = 0
  }
  None
}

///|
/// Python `(year, mmask/mdaymask)` of day index `i` as a datetime at `t`.
fn RruleGen::make(
  self : RruleGen,
  i : Int,
  t : (Int, Int, Int),
) -> @datetime.DateTime raise @datetime.DateTimeError {
  let ii = self.ii
  let year = if i >= ii.yearlen { self.year + 1 } else { self.year }
  @datetime.DateTime::new(
    year,
    ii.mmask[i],
    ii.mdaymask[i],
    hour=t.0,
    minute=t.1,
    second=t.2,
    tzinfo?=self.rr.tzinfo,
  )
}

///|
/// `datetime.date(year, month, day).toordinal() - yearordinal`.
fn RruleGen::day_index(self : RruleGen) -> Int raise @datetime.DateTimeError {
  if self.day < 1 || self.day > @datetime.days_in_month(self.year, self.month) {
    raise @datetime.ValueError("day is out of range for month")
  }
  @datetime.ymd_to_ordinal(self.year, self.month, self.day) -
  self.ii.yearordinal
}

///|
/// Whether day index `i` is removed by the by-rules.
fn RruleGen::excluded(self : RruleGen, i : Int) -> Bool {
  let rr = self.rr
  let ii = self.ii
  let t = rr.tables
  if rr.bymonth is Some(bm) && !bm.is_empty() && !t.bymonth[ii.mmask[i]] {
    return true
  }
  if rr.byweekno is Some(bw) && !bw.is_empty() {
    match ii.wnomask {
      Some(m) => if !m[i] { return true }
      None => ()
    }
  }
  if rr.byweekday is Some(bw) &&
    !bw.is_empty() &&
    !t.byweekday[(ii.yearweekday + i) % 7] {
    return true
  }
  if ii.nwdaymask is Some(m) && !m[i] {
    return true
  }
  if rr.byeaster is Some(be) && !be.is_empty() {
    match ii.eastermask {
      Some(m) => if !m[i] { return true }
      None => ()
    }
  }
  if (!rr.bymonthday.is_empty() || !rr.bynmonthday.is_empty()) &&
    !t.bymonthday[ii.mdaymask[i]] &&
    !t.bynmonthday[-ii.nmdaymask[i]] {
    return true
  }
  if rr.byyearday is Some(by) && !by.is_empty() {
    let yt = t.byyearday
    let ok = if i < ii.yearlen {
      in_table(yt, i + 1 + 366) || in_table(yt, -ii.yearlen + i + 366)
    } else {
      in_table(yt, i + 1 - ii.yearlen + 366) ||
      in_table(yt, -ii.nextyearlen + i - ii.yearlen + 366)
    }
    if !ok {
      return true
    }
  }
  false
}

///|
/// Expand the current period into `buf` (Python: getdayset, the filter
/// loop and the output loops).
fn RruleGen::expand(self : RruleGen) -> Unit raise @datetime.DateTimeError {
  let rr = self.rr
  let ii = self.ii
  self.buf.clear()
  self.pos = 0
  self.day_pos = 0
  self.time_pos = 0
  // getdayset
  let (start, end) = match rr.freq {
    Yearly => (0, ii.yearlen)
    Monthly => ii.month_range(self.month)
    Weekly => {
      // We need to handle cross-year weeks here.
      let mut i = self.day_index()
      let start = i
      for _ in 0..<7 {
        i += 1
        // This will cross the year boundary, if necessary.
        if ii.wday(i) == rr.wkst {
          break
        }
      }
      (start, i)
    }
    _ => {
      let i = self.day_index()
      (i, i + 1)
    }
  }
  // Do the "hard" work ;-)
  self.filtered = false
  let kept = self.kept
  kept.clear()
  for i in start..<end {
    if self.excluded(i) {
      self.filtered = true
    } else {
      kept.push(i)
    }
  }
  // Output results
  let timeset = self.timeset
  if rr.bysetpos is Some(bysetpos) &&
    !bysetpos.is_empty() &&
    !timeset.is_empty() {
    let tlen = timeset.length()
    let poslist : Array[@datetime.DateTime] = []
    for pos in bysetpos {
      let (daypos, timepos) = if pos < 0 {
        (@datetime.floor_div(pos, tlen), @datetime.floor_mod(pos, tlen))
      } else {
        (@datetime.floor_div(pos - 1, tlen), @datetime.floor_mod(pos - 1, tlen))
      }
      match py_index(kept.length(), daypos) {
        None => ()
        Some(k) => {
          let res = self.make(kept[k], timeset[timepos])
          if !poslist.contains(res) {
            poslist.push(res)
          }
        }
      }
    }
    stable_sort(poslist, dt_lt)
    self.buf.append(poslist)
    // the kept days are consumed through `buf`
    self.day_pos = kept.length()
  }
}

// Advancing uses `Int64` arithmetic: Python integers do not overflow, and
// the intermediate values (e.g. `hour + interval`) can exceed `Int` for
// large intervals.

///|
fn fdiv64(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a % b != 0L && (a < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
fn fmod64(a : Int64, b : Int64) -> Int64 {
  let r = a % b
  if r != 0L && (r < 0L) != (b < 0L) {
    r + b
  } else {
    r
  }
}

///|
/// Python `a // b` on Int64 (raises for `b == 0`).
fn py_floordiv64(a : Int64, b : Int64) -> Int64 raise @datetime.DateTimeError {
  if b == 0L {
    raise @datetime.ValueError("integer division or modulo by zero")
  }
  fdiv64(a, b)
}

///|
/// Clamp a day number to `Int`. Values beyond the clamp are equivalent: a
/// day past ~4M overflows MAXYEAR and one below 1 is invalid either way.
fn clamp_day(d : Int64) -> Int {
  if d > 100_000_000L {
    100_000_000
  } else if d < -100_000_000L {
    -100_000_000
  } else {
    d.to_int()
  }
}

///|
/// Python `__mod_distance`: the next value in `byxxx` reachable by adding
/// `interval`, as `(carry, value)`.
fn RruleGen::mod_distance(
  self : RruleGen,
  value : Int64,
  byxxx : FixedArray[Bool],
  base : Int,
) -> (Int64, Int) raise @datetime.DateTimeError {
  let interval = self.rr.interval.to_int64()
  let b = base.to_int64()
  let mut accumulator = 0L
  let mut value = value
  for _ in 1..<=base {
    let div = fdiv64(value + interval, b)
    value = fmod64(value + interval, b)
    accumulator += div
    if in_table(byxxx, value.to_int()) {
      return (accumulator, value.to_int())
    }
  }
  // Python returns None, and the caller's tuple unpacking fails.
  raise @datetime.TypeError("cannot unpack non-iterable NoneType object")
}

///|
/// Advance to the next period ("Handle frequency and interval"). Returns
/// `false` when the iteration ends (year > MAXYEAR).
fn RruleGen::advance(self : RruleGen) -> Bool raise @datetime.DateTimeError {
  let rr = self.rr
  let interval = rr.interval.to_int64()
  let t = rr.tables
  let has_byhour = rr.byhour is Some(b) && !b.is_empty()
  let has_byminute = rr.byminute is Some(b) && !b.is_empty()
  let has_bysecond = rr.bysecond is Some(b) && !b.is_empty()
  let maxyear = @datetime.MAXYEAR.to_int64()
  let mut fixday = false
  let mut day = self.day.to_int64()
  match rr.freq {
    Yearly => {
      let year = self.year.to_int64() + interval
      if year > maxyear {
        return false
      }
      self.year = year.to_int()
      self.ii.rebuild(self.year, self.month)
    }
    Monthly => {
      let mut month = self.month.to_int64() + interval
      let mut year = self.year.to_int64()
      if month > 12L {
        let div = fdiv64(month, 12L)
        month = fmod64(month, 12L)
        year += div
        if month == 0L {
          month = 12L
          year -= 1L
        }
        if year > maxyear {
          return false
        }
      }
      self.year = year.to_int()
      self.month = month.to_int()
      self.ii.rebuild(self.year, self.month)
    }
    Weekly => {
      let wkst = rr.wkst
      if wkst > self.weekday {
        day += (-(self.weekday + 1 + (6 - wkst))).to_int64() + interval * 7L
      } else {
        day += (-(self.weekday - wkst)).to_int64() + interval * 7L
      }
      self.weekday = wkst
      fixday = true
    }
    Daily => {
      day += interval
      fixday = true
    }
    Hourly => {
      let mut hour = self.hour.to_int64()
      if self.filtered {
        // Jump to one iteration before next day
        hour += py_floordiv64(23L - hour, interval) * interval
      }
      let (ndays, h) = if has_byhour {
        self.mod_distance(hour, t.byhour, 24)
      } else {
        (fdiv64(hour + interval, 24L), fmod64(hour + interval, 24L).to_int())
      }
      self.hour = h
      if ndays != 0L {
        day += ndays
        fixday = true
      }
      self.timeset = self.gettimeset()
    }
    Minutely => {
      let mut minute = self.minute.to_int64()
      if self.filtered {
        // Jump to one iteration before next day
        minute += py_floordiv64(
            1439L - (self.hour.to_int64() * 60L + minute),
            interval,
          ) *
          interval
      }
      let mut valid = false
      let rep_rate = 24 * 60
      for _ in 0..<(rep_rate / gcd(rr.interval, rep_rate)) {
        let (nhours, m) = if has_byminute {
          self.mod_distance(minute, t.byminute, 60)
        } else {
          (
            fdiv64(minute + interval, 60L),
            fmod64(minute + interval, 60L).to_int(),
          )
        }
        minute = m.to_int64()
        let hour = self.hour.to_int64() + nhours
        let div = fdiv64(hour, 24L)
        self.hour = fmod64(hour, 24L).to_int()
        if div != 0L {
          day += div
          fixday = true
          self.filtered = false
        }
        if !has_byhour || in_table(t.byhour, self.hour) {
          valid = true
          break
        }
      }
      self.minute = minute.to_int()
      if !valid {
        raise @datetime.ValueError(
          "Invalid combination of interval and byhour resulting in empty rule.",
        )
      }
      self.timeset = self.gettimeset()
    }
    Secondly => {
      let mut second = self.second.to_int64()
      if self.filtered {
        // Jump to one iteration before next day
        second += py_floordiv64(
            86399L -
            (
              self.hour.to_int64() * 3600L +
              self.minute.to_int64() * 60L +
              second
            ),
            interval,
          ) *
          interval
      }
      let rep_rate = 24 * 3600
      let mut valid = false
      for _ in 0..<(rep_rate / gcd(rr.interval, rep_rate)) {
        let (nminutes, s) = if has_bysecond {
          self.mod_distance(second, t.bysecond, 60)
        } else {
          (
            fdiv64(second + interval, 60L),
            fmod64(second + interval, 60L).to_int(),
          )
        }
        second = s.to_int64()
        let minute = self.minute.to_int64() + nminutes
        let div = fdiv64(minute, 60L)
        self.minute = fmod64(minute, 60L).to_int()
        if div != 0L {
          let hour = self.hour.to_int64() + div
          let div = fdiv64(hour, 24L)
          self.hour = fmod64(hour, 24L).to_int()
          if div != 0L {
            day += div
            fixday = true
          }
        }
        if (!has_byhour || in_table(t.byhour, self.hour)) &&
          (!has_byminute || in_table(t.byminute, self.minute)) &&
          (!has_bysecond || in_table(t.bysecond, second.to_int())) {
          valid = true
          break
        }
      }
      self.second = second.to_int()
      if !valid {
        raise @datetime.ValueError(
          "Invalid combination of interval, byhour and byminute resulting in empty rule.",
        )
      }
      self.timeset = self.gettimeset()
    }
  }
  self.day = clamp_day(day)
  if fixday && self.day > 28 {
    if self.day > 5_000_000 {
      // more days than in 10000 years: the loop below would pass MAXYEAR
      return false
    }
    let mut daysinmonth = @datetime.days_in_month(self.year, self.month)
    if self.day > daysinmonth {
      while self.day > daysinmonth {
        self.day -= daysinmonth
        self.month += 1
        if self.month == 13 {
          self.month = 1
          self.year += 1
          if self.year > @datetime.MAXYEAR {
            return false
          }
        }
        daysinmonth = @datetime.days_in_month(self.year, self.month)
      }
      self.ii.rebuild(self.year, self.month)
    }
  }
  true
}
