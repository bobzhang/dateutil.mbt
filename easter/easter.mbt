///|
/// The Easter computation method (dateutil `EASTER_JULIAN`,
/// `EASTER_ORTHODOX`, `EASTER_WESTERN`).
pub(all) enum EasterMethod {
  /// Original calculation in the Julian calendar, valid after 326 AD.
  Julian
  /// Original method, with the date converted to the Gregorian calendar,
  /// valid in years 1583 to 4099.
  Orthodox
  /// Revised method in the Gregorian calendar, valid in years 1583 to 4099.
  Western
} derive(Eq, Debug)

///|
/// dateutil's integer method codes: 1 = Julian, 2 = Orthodox, 3 = Western.
pub fn EasterMethod::from_int(
  code : Int,
) -> EasterMethod raise @datetime.DateTimeError {
  match code {
    1 => Julian
    2 => Orthodox
    3 => Western
    _ => raise @datetime.ValueError("invalid method")
  }
}

///|
/// The integer code of a method (inverse of `from_int`).
pub fn EasterMethod::to_int(self : EasterMethod) -> Int {
  match self {
    Julian => 1
    Orthodox => 2
    Western => 3
  }
}

///|
/// Python floor division `//`.
fn fdiv(a : Int, b : Int) -> Int {
  @datetime.floor_div(a, b)
}

///|
/// Python modulo `%`.
fn fmod(a : Int, b : Int) -> Int {
  @datetime.floor_mod(a, b)
}

///|
/// Date of Easter Sunday in `year`, ported from GM Arts' algorithm (based on
/// Claus Tondering's), as in `dateutil.easter.easter`. The default method is
/// `Western`. Raises `ValueError` if the computed date is not a valid date
/// (years outside 1..=9999).
///
/// ```mbt check
/// test {
///   inspect(@easter.easter(2024), content="2024-03-31")
///   inspect(@easter.easter(2024, variant=Orthodox), content="2024-05-05")
///   inspect(@easter.easter(2024, variant=Julian), content="2024-04-22")
/// }
/// ```
pub fn easter(
  year : Int,
  variant? : EasterMethod = Western,
) -> @datetime.Date raise @datetime.DateTimeError {
  // g - Golden year - 1
  // c - Century
  // h - (23 - Epact) mod 30
  // i - Number of days from March 21 to Paschal Full Moon
  // j - Weekday for PFM (0=Sunday, etc)
  // p - Number of days from March 21 to Sunday on or before PFM
  //     (-6 to 28 methods 1 & 3, to 56 for method 2)
  // e - Extra days to add for method 2 (converting Julian
  //     date to Gregorian date)
  let y = year
  let g = fmod(y, 19)
  let mut e = 0
  let (i, j) = match variant {
    Julian | Orthodox => {
      // Old method
      let i = fmod(19 * g + 15, 30)
      let j = fmod(y + fdiv(y, 4) + i, 7)
      if variant is Orthodox {
        // Extra dates to convert Julian to Gregorian date
        e = 10
        if y > 1600 {
          e = e + fdiv(y, 100) - 16 - fdiv(fdiv(y, 100) - 16, 4)
        }
      }
      (i, j)
    }
    Western => {
      // New method
      let c = fdiv(y, 100)
      let h = fmod(c - fdiv(c, 4) - fdiv(8 * c + 13, 25) + 19 * g + 15, 30)
      let i = h -
        fdiv(h, 28) * (1 - fdiv(h, 28) * fdiv(29, h + 1) * fdiv(21 - g, 11))
      let j = fmod(y + fdiv(y, 4) + i + 2 - c + fdiv(c, 4), 7)
      (i, j)
    }
  }
  // p can be from -6 to 56 corresponding to dates 22 March to 23 May
  // (later dates apply to method 2, although 23 May never actually occurs)
  let p = i - j + e
  let d = 1 + fmod(p + 27 + fdiv(p + 6, 40), 31)
  let m = 3 + fdiv(p + 26, 30)
  @datetime.Date::new(y, m, d)
}
