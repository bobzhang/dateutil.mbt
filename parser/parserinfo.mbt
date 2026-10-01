// dateutil `parserinfo`: the word tables and hooks the parser consults.
//
// Python customizes `parserinfo` by subclassing and overriding the class
// attributes (`JUMP`, `WEEKDAYS`, `MONTHS`, ...) or methods
// (`convertyear`, ...). Here every table is an optional constructor
// argument (defaulting to dateutil's English tables) and the overridable
// methods are optional hook closures.

///|
/// dateutil `parserinfo.JUMP`: words/characters skipped between date parts.
pub let default_jump : Array[String] = [
  " ", ".", ",", ";", "-", "/", "'", "at", "on", "and", "ad", "m", "t", "of", "st",
  "nd", "rd", "th",
]

///|
/// dateutil `parserinfo.WEEKDAYS` (Monday first).
pub let default_weekdays : Array[Array[String]] = [
  ["Mon", "Monday"],
  ["Tue", "Tuesday"],
  ["Wed", "Wednesday"],
  ["Thu", "Thursday"],
  ["Fri", "Friday"],
  ["Sat", "Saturday"],
  ["Sun", "Sunday"],
]

///|
/// dateutil `parserinfo.MONTHS`.
pub let default_months : Array[Array[String]] = [
  ["Jan", "January"],
  ["Feb", "February"],
  ["Mar", "March"],
  ["Apr", "April"],
  ["May", "May"],
  ["Jun", "June"],
  ["Jul", "July"],
  ["Aug", "August"],
  ["Sep", "Sept", "September"],
  ["Oct", "October"],
  ["Nov", "November"],
  ["Dec", "December"],
]

///|
/// dateutil `parserinfo.HMS`.
pub let default_hms : Array[Array[String]] = [
  ["h", "hour", "hours"],
  ["m", "minute", "minutes"],
  ["s", "second", "seconds"],
]

///|
/// dateutil `parserinfo.AMPM`.
pub let default_ampm : Array[Array[String]] = [["am", "a"], ["pm", "p"]]

///|
/// dateutil `parserinfo.UTCZONE`.
pub let default_utczone : Array[String] = ["UTC", "GMT", "Z", "z"]

///|
/// dateutil `parserinfo.PERTAIN`.
pub let default_pertain : Array[String] = ["of"]

///|
/// dateutil `parserinfo`: which inputs the parser accepts.
///
/// Build one with `ParserInfo::new`, overriding any of the tables (Python:
/// subclass attributes) or the `convertyear` hook (Python: method override).
pub struct ParserInfo {
  /// `parserinfo.dayfirst`
  dayfirst : Bool
  /// `parserinfo.yearfirst`
  yearfirst : Bool
  /// The raw `UTCZONE` list (used case-sensitively by the parser).
  utczone_list : Array[String]
  /// `TZOFFSET`: tz names with a known offset in seconds.
  tzoffsets : Map[String, Int]
  /// `parserinfo._year`: the reference year for two-digit years.
  year : Int
  /// `parserinfo._century`
  century : Int
  priv jump_set : Map[String, Int]
  priv weekdays_map : Map[String, Int]
  priv months_map : Map[String, Int]
  priv hms_map : Map[String, Int]
  priv ampm_map : Map[String, Int]
  priv utczone_map : Map[String, Int]
  priv pertain_map : Map[String, Int]
  priv convertyear_hook : ((ParserInfo, Int, Bool) -> Int)?
}

///|
/// `parserinfo._convert` for a table of alias groups.
fn convert_groups(lst : Array[Array[String]]) -> Map[String, Int] {
  let dct = Map([])
  for i, group in lst {
    for v in group {
      dct[py_lower(v)] = i
    }
  }
  dct
}

///|
/// `parserinfo._convert` for a flat table.
fn convert_flat(lst : Array[String]) -> Map[String, Int] {
  let dct = Map([])
  for i, v in lst {
    dct[py_lower(v)] = i
  }
  dct
}

///|
/// Creates a `parserinfo`.
///
/// * `dayfirst` / `yearfirst`: defaults for ambiguous numeric dates.
/// * `jump`, `weekdays`, `months`, `hms`, `ampm`, `utczone`, `pertain`,
///   `tzoffset`: the Python class attributes `JUMP`, `WEEKDAYS`, `MONTHS`,
///   `HMS`, `AMPM`, `UTCZONE`, `PERTAIN`, `TZOFFSET`. Each inner array of the
///   grouped tables lists aliases for one entry (Python: a tuple or a
///   single string).
/// * `year`: the reference "current" year used to expand two-digit years
///   (Python sets `_year` from `time.localtime()`); defaults to the current
///   local year.
/// * `convertyear`: replaces `parserinfo.convertyear(year,
///   century_specified)`; call `ParserInfo::default_convertyear` from it to
///   reach the base behaviour (Python: `super().convertyear`).
///
/// ```mbt check
/// test {
///   let info = @parser.ParserInfo::new(weekdays=[
///     ["Mo", "Montag"],
///     ["Di", "Dienstag"],
///     ["Mi", "Mittwoch"],
///     ["Do", "Donnerstag"],
///     ["Fr", "Freitag"],
///     ["Sa", "Samstag"],
///     ["So", "Sonntag"],
///   ])
///   let dt = @parser.parse("Sa 21. Jan 2017", parserinfo=info)
///   inspect(dt, content="2017-01-21 00:00:00")
/// }
/// ```
pub fn ParserInfo::new(
  dayfirst? : Bool = false,
  yearfirst? : Bool = false,
  jump? : Array[String] = default_jump,
  weekdays? : Array[Array[String]] = default_weekdays,
  months? : Array[Array[String]] = default_months,
  hms? : Array[Array[String]] = default_hms,
  ampm? : Array[Array[String]] = default_ampm,
  utczone? : Array[String] = default_utczone,
  pertain? : Array[String] = default_pertain,
  tzoffset? : Map[String, Int] = {},
  year? : Int,
  convertyear? : (ParserInfo, Int, Bool) -> Int,
) -> ParserInfo {
  let year = match year {
    Some(y) => y
    None => @datetime.DateTime::now().year
  }
  {
    dayfirst,
    yearfirst,
    utczone_list: utczone,
    tzoffsets: tzoffset,
    year,
    century: @datetime.floor_div(year, 100) * 100,
    jump_set: convert_flat(jump),
    weekdays_map: convert_groups(weekdays),
    months_map: convert_groups(months),
    hms_map: convert_groups(hms),
    ampm_map: convert_groups(ampm),
    utczone_map: convert_flat(utczone),
    pertain_map: convert_flat(pertain),
    convertyear_hook: convertyear,
  }
}

///|
/// `parserinfo.jump(name)`
pub fn ParserInfo::jump(self : ParserInfo, name : String) -> Bool {
  self.jump_set.contains(py_lower(name))
}

///|
/// `parserinfo.weekday(name)`: 0 (Monday) .. 6, or `None`.
pub fn ParserInfo::weekday(self : ParserInfo, name : String) -> Int? {
  self.weekdays_map.get(py_lower(name))
}

///|
/// `parserinfo.month(name)`: 1 .. 12, or `None`.
pub fn ParserInfo::month(self : ParserInfo, name : String) -> Int? {
  self.months_map.get(py_lower(name)).map(m => m + 1)
}

///|
/// `parserinfo.hms(name)`: 0 = hours, 1 = minutes, 2 = seconds.
pub fn ParserInfo::hms(self : ParserInfo, name : String) -> Int? {
  self.hms_map.get(py_lower(name))
}

///|
/// `parserinfo.ampm(name)`: 0 = AM, 1 = PM.
pub fn ParserInfo::ampm(self : ParserInfo, name : String) -> Int? {
  self.ampm_map.get(py_lower(name))
}

///|
/// `parserinfo.pertain(name)`
pub fn ParserInfo::pertain(self : ParserInfo, name : String) -> Bool {
  self.pertain_map.contains(py_lower(name))
}

///|
/// `parserinfo.utczone(name)`
pub fn ParserInfo::utczone(self : ParserInfo, name : String) -> Bool {
  self.utczone_map.contains(py_lower(name))
}

///|
/// `parserinfo.tzoffset(name)`. Like dateutil, the UTC check compares the
/// name as-is against the lower-cased `UTCZONE` keys (so only `"z"` hits).
pub fn ParserInfo::tzoffset(self : ParserInfo, name : String) -> Int? {
  if self.utczone_map.contains(name) {
    return Some(0)
  }
  self.tzoffsets.get(name)
}

///|
/// The base `parserinfo.convertyear`: converts two-digit years to a year
/// within [-50, 49] of `self.year`.
pub fn ParserInfo::default_convertyear(
  self : ParserInfo,
  year : Int,
  century_specified? : Bool = false,
) -> Int {
  if year < 100 && !century_specified {
    // assume current century to start
    let year = year + self.century
    if year >= self.year + 50 {
      year - 100
    } else if year < self.year - 50 {
      year + 100
    } else {
      year
    }
  } else {
    year
  }
}

///|
/// `parserinfo.convertyear(year, century_specified)`, honouring the
/// `convertyear` hook.
pub fn ParserInfo::convertyear(
  self : ParserInfo,
  year : Int,
  century_specified? : Bool = false,
) -> Int {
  match self.convertyear_hook {
    Some(f) => f(self, year, century_specified)
    None => self.default_convertyear(year, century_specified~)
  }
}
