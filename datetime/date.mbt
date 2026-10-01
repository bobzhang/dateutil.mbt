///|
/// A calendar date (Python `datetime.date`), proleptic Gregorian,
/// `MINYEAR <= year <= MAXYEAR`.
pub struct Date {
  year : Int
  month : Int
  day : Int
} derive(Eq, Compare, Hash)

///|
/// `date(year, month, day)`; raises `ValueError` for out-of-range fields.
pub fn Date::new(
  year : Int,
  month : Int,
  day : Int,
) -> Date raise DateTimeError {
  check_date_fields(year, month, day)
  { year, month, day, }
}

///|
/// `date.fromordinal(n)`.
pub fn Date::from_ordinal(n : Int) -> Date raise DateTimeError {
  if n < 1 || n > MAXORDINAL {
    raise ValueError("ordinal must be >= 1")
  }
  let (year, month, day) = ordinal_to_ymd(n)
  { year, month, day, }
}

///|
/// `date.fromisocalendar(year, week, day)`.
pub fn Date::from_isocalendar(
  year : Int,
  week : Int,
  day : Int,
) -> Date raise DateTimeError {
  if year < MINYEAR || year > MAXYEAR {
    raise ValueError("Year is out of range: \{year}")
  }
  if week <= 0 || week >= 53 {
    let mut out_of_range = true
    if week == 53 {
      // ISO years have 53 weeks in them on years starting with a
      // Thursday and leap years starting on a Wednesday
      let first_weekday = floor_mod(ymd_to_ordinal(year, 1, 1), 7)
      if first_weekday == 4 || (first_weekday == 3 && is_leap(year)) {
        out_of_range = false
      }
    }
    if out_of_range {
      raise ValueError("Invalid week: \{week}")
    }
  }
  if day <= 0 || day > 7 {
    raise ValueError("Invalid weekday: \{day} (range is [1, 7])")
  }
  let day_offset = (week - 1) * 7 + (day - 1)
  let day_1 = iso_week1_monday(year)
  Date::from_ordinal(day_1 + day_offset)
}

///|
fn iso_week1_monday(year : Int) -> Int {
  let firstday = ymd_to_ordinal(year, 1, 1)
  let firstweekday = floor_mod(firstday + 6, 7)
  let week1monday = firstday - firstweekday
  if firstweekday > 3 {
    week1monday + 7
  } else {
    week1monday
  }
}

///|
fn iso_calendar_of(year : Int, month : Int, day : Int) -> (Int, Int, Int) {
  let mut year = year
  let mut week1monday = iso_week1_monday(year)
  let today = ymd_to_ordinal(year, month, day)
  let mut week = floor_div(today - week1monday, 7)
  let mut wd = floor_mod(today - week1monday, 7)
  if week < 0 {
    year -= 1
    week1monday = iso_week1_monday(year)
    week = floor_div(today - week1monday, 7)
    wd = floor_mod(today - week1monday, 7)
  } else if week >= 52 {
    if today >= iso_week1_monday(year + 1) {
      year += 1
      week = 0
    }
  }
  (year, week + 1, wd + 1)
}

///|
/// `date.today()` in local time.
pub fn Date::today() -> Date {
  DateTime::now().date()
}

///|
pub fn Date::to_ordinal(self : Date) -> Int {
  ymd_to_ordinal(self.year, self.month, self.day)
}

///|
/// Monday == 0 ... Sunday == 6.
pub fn Date::weekday(self : Date) -> Int {
  floor_mod(self.to_ordinal() + 6, 7)
}

///|
/// Monday == 1 ... Sunday == 7.
pub fn Date::isoweekday(self : Date) -> Int {
  self.weekday() + 1
}

///|
/// `(iso_year, iso_week, iso_weekday)`.
pub fn Date::isocalendar(self : Date) -> (Int, Int, Int) {
  iso_calendar_of(self.year, self.month, self.day)
}

///|
/// `date.replace(...)`.
pub fn Date::replace(
  self : Date,
  year? : Int,
  month? : Int,
  day? : Int,
) -> Date raise DateTimeError {
  Date::new(
    year.unwrap_or(self.year),
    month.unwrap_or(self.month),
    day.unwrap_or(self.day),
  )
}

///|
/// `date + timedelta` (only the `days` component matters).
pub fn Date::add(self : Date, delta : TimeDelta) -> Date raise DateTimeError {
  let o = self.to_ordinal().to_int64() + delta.days.to_int64()
  if o > 0L && o <= MAXORDINAL.to_int64() {
    Date::from_ordinal(o.to_int())
  } else {
    raise OverflowError("result out of range")
  }
}

///|
/// `date - timedelta`.
pub fn Date::sub(self : Date, delta : TimeDelta) -> Date raise DateTimeError {
  // CPython uses only `delta.days` (sub-day parts are ignored, not negated).
  let o = self.to_ordinal().to_int64() - delta.days.to_int64()
  if o > 0L && o <= MAXORDINAL.to_int64() {
    Date::from_ordinal(o.to_int())
  } else {
    raise OverflowError("result out of range")
  }
}

///|
/// `date - date`.
pub fn Date::diff(self : Date, other : Date) -> TimeDelta {
  TimeDelta::new(days=self.to_ordinal() - other.to_ordinal())
}

///|
/// `YYYY-MM-DD`.
pub fn Date::isoformat(self : Date) -> String {
  "\{pad(self.year, 4)}-\{pad(self.month, 2)}-\{pad(self.day, 2)}"
}

///|
/// Python `str(date)` (ISO format).
pub impl Show for Date with fn output(self, logger) {
  logger.write_string(self.isoformat())
}

///|
/// Python `repr(date)`.
pub fn Date::repr(self : Date) -> String {
  "datetime.date(\{self.year}, \{self.month}, \{self.day})"
}

///|
/// `time.struct_time`-like broken-down time.
pub struct TimeTuple {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  /// Monday == 0
  weekday : Int
  /// 1-based day of the year
  yday : Int
  /// 1, 0 or -1 (unknown)
  isdst : Int
} derive(Eq, Debug)

///|
pub fn Date::timetuple(self : Date) -> TimeTuple {
  {
    year: self.year,
    month: self.month,
    day: self.day,
    hour: 0,
    minute: 0,
    second: 0,
    weekday: self.weekday(),
    yday: days_before_month(self.year, self.month) + self.day,
    isdst: -1,
  }
}

///|
/// `date.ctime()`, e.g. `Thu Sep 25 00:00:00 2003`.
pub fn Date::ctime(self : Date) -> String {
  ctime_of(self.year, self.month, self.day, 0, 0, 0)
}
