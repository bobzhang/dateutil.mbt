// `rrule._iter`: the recurrence generator, as a resumable state machine.
// Each "period" (year/month/week/day/hour/... depending on `freq`) is
// expanded into a buffer of candidate datetimes, which are then filtered by
// `until`/`dtstart`/`count` one at a time, exactly like the Python
// generator's inner loops.

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
  buf : Array[@datetime.DateTime]
  mut pos : Int
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
  None
}

///|
fn RruleGen::next(
  self : RruleGen,
) -> @datetime.DateTime? raise @datetime.DateTimeError {
  let rr = self.rr
  for ;; {
    while self.pos < self.buf.length() {
      let res = self.buf[self.pos]
      self.pos += 1
      if rr.until is Some(until) && res.compare(until) > 0 {
        return self.finish()
      } else if res.compare(rr.dtstart) >= 0 {
        if self.count is Some(c) {
          self.count = Some(c - 1)
          if c - 1 < 0 {
            return self.finish()
          }
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
  // getdayset
  let (start, end) = match rr.freq {
    Yearly => (0, ii.yearlen)
    Monthly => (ii.mrange[self.month - 1], ii.mrange[self.month])
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
  } else {
    for i in kept {
      for t in timeset {
        self.buf.push(self.make(i, t))
      }
    }
  }
}

///|
/// Python `__mod_distance`: the next value in `byxxx` reachable by adding
/// `interval`, as `(carry, value)`.
fn RruleGen::mod_distance(
  self : RruleGen,
  value : Int,
  byxxx : FixedArray[Bool],
  base : Int,
) -> (Int, Int) raise @datetime.DateTimeError {
  let interval = self.rr.interval
  let mut accumulator = 0
  let mut value = value
  for _ in 1..<=base {
    let div = @datetime.floor_div(value + interval, base)
    value = @datetime.floor_mod(value + interval, base)
    accumulator += div
    if in_table(byxxx, value) {
      return (accumulator, value)
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
  let interval = rr.interval
  let t = rr.tables
  let has_byhour = rr.byhour is Some(b) && !b.is_empty()
  let has_byminute = rr.byminute is Some(b) && !b.is_empty()
  let has_bysecond = rr.bysecond is Some(b) && !b.is_empty()
  let mut fixday = false
  match rr.freq {
    Yearly => {
      self.year += interval
      if self.year > @datetime.MAXYEAR {
        return false
      }
      self.ii.rebuild(self.year, self.month)
    }
    Monthly => {
      self.month += interval
      if self.month > 12 {
        let div = @datetime.floor_div(self.month, 12)
        let mod_ = @datetime.floor_mod(self.month, 12)
        self.month = mod_
        self.year += div
        if self.month == 0 {
          self.month = 12
          self.year -= 1
        }
        if self.year > @datetime.MAXYEAR {
          return false
        }
      }
      self.ii.rebuild(self.year, self.month)
    }
    Weekly => {
      let wkst = rr.wkst
      if wkst > self.weekday {
        self.day += -(self.weekday + 1 + (6 - wkst)) + interval * 7
      } else {
        self.day += -(self.weekday - wkst) + interval * 7
      }
      self.weekday = wkst
      fixday = true
    }
    Daily => {
      self.day += interval
      fixday = true
    }
    Hourly => {
      if self.filtered {
        // Jump to one iteration before next day
        self.hour += py_floordiv(23 - self.hour, interval) * interval
      }
      let (ndays, hour) = if has_byhour {
        self.mod_distance(self.hour, t.byhour, 24)
      } else {
        (
          @datetime.floor_div(self.hour + interval, 24),
          @datetime.floor_mod(self.hour + interval, 24),
        )
      }
      self.hour = hour
      if ndays != 0 {
        self.day += ndays
        fixday = true
      }
      self.timeset = self.gettimeset()
    }
    Minutely => {
      if self.filtered {
        // Jump to one iteration before next day
        self.minute += py_floordiv(
            1439 - (self.hour * 60 + self.minute),
            interval,
          ) *
          interval
      }
      let mut valid = false
      let rep_rate = 24 * 60
      for _ in 0..<(rep_rate / gcd(interval, rep_rate)) {
        let (nhours, minute) = if has_byminute {
          self.mod_distance(self.minute, t.byminute, 60)
        } else {
          (
            @datetime.floor_div(self.minute + interval, 60),
            @datetime.floor_mod(self.minute + interval, 60),
          )
        }
        self.minute = minute
        let div = @datetime.floor_div(self.hour + nhours, 24)
        self.hour = @datetime.floor_mod(self.hour + nhours, 24)
        if div != 0 {
          self.day += div
          fixday = true
          self.filtered = false
        }
        if !has_byhour || in_table(t.byhour, self.hour) {
          valid = true
          break
        }
      }
      if !valid {
        raise @datetime.ValueError(
          "Invalid combination of interval and byhour resulting in empty rule.",
        )
      }
      self.timeset = self.gettimeset()
    }
    Secondly => {
      if self.filtered {
        // Jump to one iteration before next day
        self.second += py_floordiv(
            86399 - (self.hour * 3600 + self.minute * 60 + self.second),
            interval,
          ) *
          interval
      }
      let rep_rate = 24 * 3600
      let mut valid = false
      for _ in 0..<(rep_rate / gcd(interval, rep_rate)) {
        let (nminutes, second) = if has_bysecond {
          self.mod_distance(self.second, t.bysecond, 60)
        } else {
          (
            @datetime.floor_div(self.second + interval, 60),
            @datetime.floor_mod(self.second + interval, 60),
          )
        }
        self.second = second
        let div = @datetime.floor_div(self.minute + nminutes, 60)
        self.minute = @datetime.floor_mod(self.minute + nminutes, 60)
        if div != 0 {
          self.hour += div
          let div = @datetime.floor_div(self.hour, 24)
          self.hour = @datetime.floor_mod(self.hour, 24)
          if div != 0 {
            self.day += div
            fixday = true
          }
        }
        if (!has_byhour || in_table(t.byhour, self.hour)) &&
          (!has_byminute || in_table(t.byminute, self.minute)) &&
          (!has_bysecond || in_table(t.bysecond, self.second)) {
          valid = true
          break
        }
      }
      if !valid {
        raise @datetime.ValueError(
          "Invalid combination of interval, byhour and byminute resulting in empty rule.",
        )
      }
      self.timeset = self.gettimeset()
    }
  }
  if fixday && self.day > 28 {
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
