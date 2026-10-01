///|
/// Per-year/per-month masks (Python `_iterinfo`).
priv struct IterInfo {
  rr : Rrule
  mut lastyear : Int?
  mut lastmonth : Int?
  mut yearlen : Int
  mut nextyearlen : Int
  mut yearordinal : Int
  mut yearweekday : Int
  mut mmask : FixedArray[Int]
  mut mrange : FixedArray[Int]
  mut mdaymask : FixedArray[Int]
  mut nmdaymask : FixedArray[Int]
  mut wnomask : FixedArray[Bool]?
  mut nwdaymask : FixedArray[Bool]?
  mut eastermask : FixedArray[Bool]?
}

///|
fn IterInfo::new(rr : Rrule) -> IterInfo {
  {
    rr,
    lastyear: None,
    lastmonth: None,
    yearlen: 0,
    nextyearlen: 0,
    yearordinal: 0,
    yearweekday: 0,
    mmask: masks_366.0,
    mrange: m366range,
    mdaymask: masks_366.1,
    nmdaymask: masks_366.2,
    wnomask: None,
    nwdaymask: None,
    eastermask: None,
  }
}

///|
/// Python `self.wdaymask[i]` where `wdaymask = WDAYMASK[wday:]`, with
/// Python negative indexing; out of range raises (Python `IndexError`).
fn IterInfo::wday(
  self : IterInfo,
  i : Int,
) -> Int raise @datetime.DateTimeError {
  let len = wdaymask_len - self.yearweekday
  if i >= 0 && i < len {
    (self.yearweekday + i) % 7
  } else if i < 0 && i >= -len {
    // WDAYMASK[wday + len + i] == (385 + i) % 7
    (wdaymask_len + i) % 7
  } else {
    raise index_error()
  }
}

///|
/// Python `self.mrange[month-1:month+1]` unpacked into `first, last`.
fn IterInfo::month_range(
  self : IterInfo,
  month : Int,
) -> (Int, Int) raise @datetime.DateTimeError {
  let s = py_slice(
    self.mrange.iter().to_array(),
    Some(month - 1),
    Some(month + 1),
    None,
  )
  guard s is [first, last] else {
    raise @datetime.ValueError(
      "not enough values to unpack (expected 2, got \{s.length()})",
    )
  }
  (first, last)
}

///|
/// Python `_iterinfo.rebuild(year, month)`.
fn IterInfo::rebuild(
  self : IterInfo,
  year : Int,
  month : Int,
) -> Unit raise @datetime.DateTimeError {
  let rr = self.rr
  let mut month = month
  if self.lastyear != Some(year) {
    self.yearlen = 365 + (if @datetime.is_leap(year) { 1 } else { 0 })
    self.nextyearlen = 365 + (if @datetime.is_leap(year + 1) { 1 } else { 0 })
    self.yearordinal = @datetime.ymd_to_ordinal(year, 1, 1)
    self.yearweekday = @datetime.weekday_of(year, 1, 1)
    let masks = if self.yearlen == 365 { masks_365 } else { masks_366 }
    self.mmask = masks.0
    self.mdaymask = masks.1
    self.nmdaymask = masks.2
    self.mrange = if self.yearlen == 365 { m365range } else { m366range }
    match rr.byweekno {
      None | Some([]) => self.wnomask = None
      Some(byweekno) => {
        let wnomask = FixedArray::make(self.yearlen + 7, false)
        let mut no1wkst = (7 - self.yearweekday + rr.wkst) % 7
        let firstwkst = no1wkst
        let wyearlen = if no1wkst >= 4 {
          no1wkst = 0
          // Number of days in the year, plus the days we got from last year.
          self.yearlen + @datetime.floor_mod(self.yearweekday - rr.wkst, 7)
        } else {
          // Number of days in the year, minus the days we left in last year.
          self.yearlen - no1wkst
        }
        let div = @datetime.floor_div(wyearlen, 7)
        let mod_ = @datetime.floor_mod(wyearlen, 7)
        let numweeks = div + mod_ / 4
        for n0 in byweekno {
          let n = if n0 < 0 { n0 + numweeks + 1 } else { n0 }
          if !(0 < n && n <= numweeks) {
            continue
          }
          let mut i = if n > 1 {
            let i = no1wkst + (n - 1) * 7
            if no1wkst != firstwkst {
              i - (7 - firstwkst)
            } else {
              i
            }
          } else {
            no1wkst
          }
          for _ in 0..<7 {
            set_mask(wnomask, i)
            i += 1
            if self.wday(i) == rr.wkst {
              break
            }
          }
        }
        if byweekno.contains(1) {
          // Check week number 1 of next year as well
          let mut i = no1wkst + numweeks * 7
          if no1wkst != firstwkst {
            i -= 7 - firstwkst
          }
          if i < self.yearlen {
            // If week starts in next year, we don't care about it.
            for _ in 0..<7 {
              set_mask(wnomask, i)
              i += 1
              if self.wday(i) == rr.wkst {
                break
              }
            }
          }
        }
        if no1wkst != 0 {
          // Check last week number of last year as well. If no1wkst is 0,
          // either the year started on week start, or week number 1 got
          // days from last year, so there are no days from last year's
          // last week number in this year.
          let lnumweeks = if !byweekno.contains(-1) {
            let lyearweekday = @datetime.weekday_of(year - 1, 1, 1)
            let lno1wkst = (7 - lyearweekday + rr.wkst) % 7
            let lyearlen = 365 +
              (if @datetime.is_leap(year - 1) { 1 } else { 0 })
            if lno1wkst >= 4 {
              52 +
              @datetime.floor_mod(
                lyearlen + @datetime.floor_mod(lyearweekday - rr.wkst, 7),
                7,
              ) /
              4
            } else {
              52 + @datetime.floor_mod(self.yearlen - no1wkst, 7) / 4
            }
          } else {
            -1
          }
          if byweekno.contains(lnumweeks) {
            for i in 0..<no1wkst {
              wnomask[i] = true
            }
          }
        }
        self.wnomask = Some(wnomask)
      }
    }
  }
  if rr.bynweekday is Some(bynweekday) &&
    !bynweekday.is_empty() &&
    (self.lastmonth != Some(month) || self.lastyear != Some(year)) {
    let ranges : Array[(Int, Int)] = []
    match rr.freq {
      Yearly =>
        match rr.bymonth {
          Some(bymonth) if !bymonth.is_empty() =>
            for m in bymonth {
              // Python rebinds the `month` loop variable here.
              month = m
              ranges.push(self.month_range(m))
            }
          _ => ranges.push((0, self.yearlen))
        }
      Monthly => ranges.push(self.month_range(month))
      _ => ()
    }
    if !ranges.is_empty() {
      // Weekly frequency won't get here, so we may not care about
      // cross-year weekly periods.
      let nwdaymask = FixedArray::make(self.yearlen, false)
      for range in ranges {
        let (first, last) = range
        let last = last - 1
        for wn in bynweekday {
          let (wday, n) = wn
          let i = if n < 0 {
            let i = last + (n + 1) * 7
            i - @datetime.floor_mod(self.wday(i) - wday, 7)
          } else {
            let i = first + (n - 1) * 7
            i + @datetime.floor_mod(7 - self.wday(i) + wday, 7)
          }
          if first <= i && i <= last {
            nwdaymask[i] = true
          }
        }
      }
      self.nwdaymask = Some(nwdaymask)
    }
  }
  match rr.byeaster {
    Some(byeaster) if !byeaster.is_empty() => {
      let len = self.yearlen + 7
      let eastermask = FixedArray::make(len, false)
      let eyday = @easter.easter(year).to_ordinal() - self.yearordinal
      for offset in byeaster {
        match py_index(len, eyday + offset) {
          Some(i) => eastermask[i] = true
          None => raise index_error()
        }
      }
      self.eastermask = Some(eastermask)
    }
    _ => ()
  }
  self.lastyear = Some(year)
  self.lastmonth = Some(month)
}

///|
/// Python `mask[i] = 1` (negative indices wrap; out of range raises).
fn set_mask(
  mask : FixedArray[Bool],
  i : Int,
) -> Unit raise @datetime.DateTimeError {
  match py_index(mask.length(), i) {
    Some(j) => mask[j] = true
    None => raise index_error()
  }
}
