///|
/// A recurrence rule (Python `dateutil.rrule.rrule`), implementing the
/// RFC 5545 RRULE semantics plus dateutil's `BYEASTER` extension.
///
/// Iteration is lazy (`iter`); results can be cached (`cache=true`).
pub struct Rrule {
  priv base : Base
  priv dtstart : @datetime.DateTime
  priv tzinfo : @datetime.Tz?
  priv freq : Freq
  priv interval : Int
  priv count : Int?
  priv until : @datetime.DateTime?
  priv wkst : Int
  priv bysetpos : Array[Int]?
  priv bymonth : Array[Int]?
  priv byyearday : Array[Int]?
  priv byeaster : Array[Int]?
  priv bymonthday : Array[Int]
  priv bynmonthday : Array[Int]
  priv byweekno : Array[Int]?
  priv byweekday : Array[Int]?
  priv bynweekday : Array[(Int, Int)]?
  priv byhour : Array[Int]?
  priv byminute : Array[Int]?
  priv bysecond : Array[Int]?
  /// For `freq < Hourly`: sorted `(h, m, s)` triples (Python `_timeset`).
  priv timeset : Array[(Int, Int, Int)]
  priv orig : OriginalRule
  priv tables : Tables
}

///|
/// The user-supplied by-rules (Python `_original_rule`), used by `Show`
/// and `replace`. `None` both for "not given" and for the `None` marker
/// Python stores for values derived from `dtstart`.
priv struct OriginalRule {
  bysetpos : Array[Int]?
  bymonth : Array[Int]?
  bymonthday : Array[Int]?
  byyearday : Array[Int]?
  byeaster : Array[Int]?
  byweekno : Array[Int]?
  byweekday : Array[Weekday]?
  byhour : Array[Int]?
  byminute : Array[Int]?
  bysecond : Array[Int]?
}

///|
/// Dense membership tables for the hot loop (Python uses `x in tuple`).
priv struct Tables {
  bymonth : FixedArray[Bool] // 0..=12
  byweekday : FixedArray[Bool] // 0..=6
  bymonthday : FixedArray[Bool] // 0..=31
  bynmonthday : FixedArray[Bool] // index -v, 0..=31
  byyearday : FixedArray[Bool] // index v + 366, 0..=732
  byhour : FixedArray[Bool] // 0..=23
  byminute : FixedArray[Bool] // 0..=59
  bysecond : FixedArray[Bool] // 0..=59
}

///|
fn table(xs : Array[Int]?, size : Int, offset? : Int = 0) -> FixedArray[Bool] {
  let t = FixedArray::make(size, false)
  if xs is Some(xs) {
    for x in xs {
      let i = x + offset
      if i >= 0 && i < size {
        t[i] = true
      }
    }
  }
  t
}

///|
fn in_table(t : FixedArray[Bool], i : Int) -> Bool {
  i >= 0 && i < t.length() && t[i]
}

///|
/// Python `__construct_byset`: keep the `BYXXX` values reachable from
/// `start` stepping by `interval` modulo `base`.
fn construct_byset(
  interval : Int,
  start : Int,
  byxxx : Array[Int],
  base : Int,
) -> Array[Int] raise @datetime.DateTimeError {
  let cset = []
  let i_gcd = gcd(interval, base)
  for num in byxxx {
    if i_gcd == 1 || @datetime.floor_mod(num - start, i_gcd) == 0 {
      cset.push(num)
    }
  }
  if cset.is_empty() {
    raise @datetime.ValueError("Invalid rrule byxxx generates an empty set.")
  }
  uniq_sorted(cset)
}

///|
/// Python `datetime.time(h, m, s)` range validation.
fn check_time(h : Int, m : Int, s : Int) -> Unit raise @datetime.DateTimeError {
  if h < 0 || h > 23 {
    raise @datetime.ValueError("hour must be in 0..23")
  }
  if m < 0 || m > 59 {
    raise @datetime.ValueError("minute must be in 0..59")
  }
  if s < 0 || s > 59 {
    raise @datetime.ValueError("second must be in 0..59")
  }
}

///|
/// Create a recurrence rule (Python `rrule(freq, dtstart=None, ...)`).
///
/// Python accepts either a single integer or a sequence for the `by*`
/// arguments; here they are arrays (pass `[x]` for a single value). An
/// empty array is distinct from omitting the argument, as in Python.
/// `wkst` defaults to Monday (`calendar.firstweekday()`). A `date`
/// `dtstart`/`until` is passed as `Date::to_datetime()`. Without
/// `dtstart`, the current time (in `until`'s zone, if aware) is used.
///
/// Raises `ValueError` for invalid `bysetpos`, unreachable `BYXXX` sets at
/// the frequency level, invalid times, or when `until` and `dtstart`
/// disagree on time-zone awareness.
///
/// ```mbt check
/// test {
///   let rr = @rrule.Rrule::new(
///     Monthly,
///     count=3,
///     byweekday=[@rrule.nth(@rrule.fr, -1)],
///     dtstart=@datetime.DateTime::new(2024, 1, 1),
///   )
///   debug_inspect(
///     rr.to_array(),
///     content=(
///       #|[
///       #|  "datetime.datetime(2024, 1, 26, 0, 0)",
///       #|  "datetime.datetime(2024, 2, 23, 0, 0)",
///       #|  "datetime.datetime(2024, 3, 29, 0, 0)",
///       #|]
///     ),
///   )
///   inspect(
///     rr,
///     content=(
///       #|DTSTART:20240101T000000
///       #|RRULE:FREQ=MONTHLY;COUNT=3;BYDAY=-1FR
///     ),
///   )
/// }
/// ```
pub fn Rrule::new(
  freq : Freq,
  dtstart? : @datetime.DateTime,
  interval? : Int = 1,
  wkst? : Weekday,
  count? : Int,
  until? : @datetime.DateTime,
  bysetpos? : Array[Int],
  bymonth? : Array[Int],
  bymonthday? : Array[Int],
  byyearday? : Array[Int],
  byeaster? : Array[Int],
  byweekno? : Array[Int],
  byweekday? : Array[Weekday],
  byhour? : Array[Int],
  byminute? : Array[Int],
  bysecond? : Array[Int],
  cache? : Bool = false,
) -> Rrule raise @datetime.DateTimeError {
  let base = Base::new(cache)
  let dtstart = match dtstart {
    Some(d) => d.replace(microsecond=0)
    None =>
      match until {
        Some({ tzinfo: Some(tz), .. }) =>
          @datetime.DateTime::now(tz~).replace(microsecond=0)
        _ => @datetime.DateTime::now().replace(microsecond=0)
      }
  }
  let tzinfo = dtstart.tzinfo
  if until is Some(u) && (dtstart.tzinfo is Some(_)) != (u.tzinfo is Some(_)) {
    // RFC 5545 3.3.10: UNTIL must be UTC when DTSTART is aware.
    raise @datetime.ValueError(
      "RRULE UNTIL values must be specified in UTC when DTSTART is timezone-aware",
    )
  }
  // Python only emits a DeprecationWarning for count + until.
  let wkst = match wkst {
    None => 0
    Some(w) => w.weekday
  }
  // bysetpos
  if bysetpos is Some(xs) {
    for pos in xs {
      if pos == 0 || !(-366 <= pos && pos <= 366) {
        raise @datetime.ValueError(
          "bysetpos must be between 1 and 366, or between -366 and -1",
        )
      }
    }
  }
  let bysetpos = bysetpos.map(xs => xs.copy())
  let orig_bysetpos = match bysetpos {
    Some(xs) if !xs.is_empty() => Some(xs)
    _ => None
  }
  // defaults derived from dtstart
  let mut bymonth = bymonth
  let mut bymonthday = bymonthday
  let mut byweekday = byweekday
  let mut bymonth_marked = false
  let mut bymonthday_marked = false
  let mut byweekday_marked = false
  if byweekno is None &&
    byyearday is None &&
    bymonthday is None &&
    byweekday is None &&
    byeaster is None {
    match freq {
      Yearly => {
        if bymonth is None {
          bymonth = Some([dtstart.month])
          bymonth_marked = true
        }
        bymonthday = Some([dtstart.day])
        bymonthday_marked = true
      }
      Monthly => {
        bymonthday = Some([dtstart.day])
        bymonthday_marked = true
      }
      Weekly => {
        byweekday = Some([weekdays[dtstart.weekday()]])
        byweekday_marked = true
      }
      _ => ()
    }
  }
  // bymonth
  let bymonth = bymonth.map(uniq_sorted)
  let orig_bymonth = if bymonth_marked { None } else { bymonth }
  // byyearday
  let byyearday = byyearday.map(uniq_sorted)
  // byeaster
  let byeaster = byeaster.map(xs => {
    let ys = xs.copy()
    ys.sort()
    ys
  })
  // bymonthday
  let (bymd, bynmd, orig_bymonthday) = match bymonthday {
    None => ([], [], None)
    Some(xs) => {
      let u = uniq_sorted(xs)
      let pos = u.filter(x => x > 0)
      let neg = u.filter(x => x < 0)
      (pos, neg, if bymonthday_marked { None } else { Some(pos + neg) })
    }
  }
  // byweekno
  let byweekno = byweekno.map(uniq_sorted)
  // byweekday / bynweekday
  let (byweekday_, bynweekday, orig_byweekday) = match byweekday {
    None => (None, None, None)
    Some(wdays) => {
      let plain = []
      let nth = []
      for w in wdays {
        match w.n {
          None | Some(0) => plain.push(w.weekday)
          Some(n) =>
            if freq > Monthly {
              plain.push(w.weekday)
            } else {
              nth.push((w.weekday, n))
            }
        }
      }
      let plain = uniq_sorted(plain)
      nth.sort()
      let nth = dedup_pairs(nth)
      let (bw, bnw) = if plain.is_empty() {
        (None, Some(nth))
      } else if nth.is_empty() {
        (Some(plain), None)
      } else {
        (Some(plain), Some(nth))
      }
      let orig : Array[Weekday] = []
      if bw is Some(p) {
        for x in p {
          orig.push(weekdays[x])
        }
      }
      if bnw is Some(p) {
        for x in p {
          orig.push(Weekday::new(x.0, n=x.1))
        }
      }
      (bw, bnw, if byweekday_marked { None } else { Some(orig) })
    }
  }
  // byhour / byminute / bysecond
  let given_byhour = byhour is Some(_)
  let byhour = match byhour {
    None => if freq < Hourly { Some([dtstart.hour]) } else { None }
    Some(xs) =>
      Some(
        if freq == Hourly {
          construct_byset(interval, dtstart.hour, xs, 24)
        } else {
          uniq_sorted(xs)
        },
      )
  }
  let given_byminute = byminute is Some(_)
  let byminute = match byminute {
    None => if freq < Minutely { Some([dtstart.minute]) } else { None }
    Some(xs) =>
      Some(
        if freq == Minutely {
          construct_byset(interval, dtstart.minute, xs, 60)
        } else {
          uniq_sorted(xs)
        },
      )
  }
  let given_bysecond = bysecond is Some(_)
  let bysecond = match bysecond {
    None => if freq < Secondly { Some([dtstart.second]) } else { None }
    Some(xs) =>
      Some(
        if freq == Secondly {
          construct_byset(interval, dtstart.second, xs, 60)
        } else {
          uniq_sorted(xs)
        },
      )
  }
  // timeset
  let timeset = []
  if freq < Hourly {
    for h in byhour.unwrap_or([]) {
      for m in byminute.unwrap_or([]) {
        for s in bysecond.unwrap_or([]) {
          check_time(h, m, s)
          timeset.push((h, m, s))
        }
      }
    }
    timeset.sort()
  }
  let orig : OriginalRule = {
    bysetpos: orig_bysetpos,
    bymonth: orig_bymonth,
    bymonthday: orig_bymonthday,
    byyearday,
    byeaster,
    byweekno,
    byweekday: orig_byweekday,
    byhour: if given_byhour {
      byhour
    } else {
      None
    },
    byminute: if given_byminute {
      byminute
    } else {
      None
    },
    bysecond: if given_bysecond {
      bysecond
    } else {
      None
    },
  }
  let tables : Tables = {
    bymonth: table(bymonth, 13),
    byweekday: table(byweekday_, 7),
    bymonthday: table(Some(bymd), 32),
    bynmonthday: table(Some(bynmd.map(x => -x)), 32),
    byyearday: table(byyearday, 733, offset=366),
    byhour: table(byhour, 24),
    byminute: table(byminute, 60),
    bysecond: table(bysecond, 60),
  }
  let rr : Rrule = {
    base,
    dtstart,
    tzinfo,
    freq,
    interval,
    count,
    until,
    wkst,
    bysetpos,
    bymonth,
    byyearday,
    byeaster,
    bymonthday: bymd,
    bynmonthday: bynmd,
    byweekno,
    byweekday: byweekday_,
    bynweekday,
    byhour,
    byminute,
    bysecond,
    timeset,
    orig,
    tables,
  }
  if cache {
    rr.base.invalidate(rr.raw_iter())
  }
  rr
}

///|
fn dedup_pairs(xs : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let out = []
  for i, x in xs {
    if i == 0 || xs[i - 1] != x {
      out.push(x)
    }
  }
  out
}

///|
/// Return a new rule with the same attributes except those given (Python
/// `rrule.replace(**kwargs)`). Nullable attributes take an `Option` so they
/// can be cleared, e.g. `replace(count=None)`; by-rules derived from
/// `dtstart` are re-derived.
pub fn Rrule::replace(
  self : Rrule,
  freq? : Freq,
  dtstart? : @datetime.DateTime,
  interval? : Int,
  wkst? : Weekday,
  count? : Int?,
  until? : @datetime.DateTime?,
  bysetpos? : Array[Int]?,
  bymonth? : Array[Int]?,
  bymonthday? : Array[Int]?,
  byyearday? : Array[Int]?,
  byeaster? : Array[Int]?,
  byweekno? : Array[Int]?,
  byweekday? : Array[Weekday]?,
  byhour? : Array[Int]?,
  byminute? : Array[Int]?,
  bysecond? : Array[Int]?,
  cache? : Bool,
) -> Rrule raise @datetime.DateTimeError {
  let o = self.orig
  Rrule::new(
    freq.unwrap_or(self.freq),
    dtstart=dtstart.unwrap_or(self.dtstart),
    interval=interval.unwrap_or(self.interval),
    wkst=wkst.unwrap_or(weekdays[self.wkst]),
    count?=count.unwrap_or(self.count),
    until?=until.unwrap_or(self.until),
    bysetpos?=bysetpos.unwrap_or(o.bysetpos),
    bymonth?=bymonth.unwrap_or(o.bymonth),
    bymonthday?=bymonthday.unwrap_or(o.bymonthday),
    byyearday?=byyearday.unwrap_or(o.byyearday),
    byeaster?=byeaster.unwrap_or(o.byeaster),
    byweekno?=byweekno.unwrap_or(o.byweekno),
    byweekday?=byweekday.unwrap_or(o.byweekday),
    byhour?=byhour.unwrap_or(o.byhour),
    byminute?=byminute.unwrap_or(o.byminute),
    bysecond?=bysecond.unwrap_or(o.bysecond),
    cache=cache.unwrap_or(self.base.cache is Some(_)),
  )
}
