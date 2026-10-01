///|
let day_abbrs : FixedArray[String] = [
  "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
]

///|
let day_names : FixedArray[String] = [
  "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
]

///|
let month_abbrs : FixedArray[String] = [
  "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
  "Dec",
]

///|
let month_names : FixedArray[String] = [
  "", "January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December",
]

///|
fn space_pad(n : Int, width : Int) -> String {
  let s = n.to_string()
  if s.length() >= width {
    s
  } else {
    " ".repeat(width - s.length()) + s
  }
}

///|
fn ctime_of(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
) -> String {
  let wd = weekday_of(year, month, day)
  "\{day_abbrs[wd]} \{month_abbrs[month]} \{space_pad(day, 2)} \{pad(hour, 2)}:\{pad(minute, 2)}:\{pad(second, 2)} \{pad(year, 4)}"
}

///|
/// Implements `strftime` for the C/POSIX locale. Supported directives:
/// `%a %A %b %B %c %d %e %f %H %I %j %m %M %p %S %U %w %W %x %X %y %Y %z
/// %Z %G %u %V %D %F %T %R %n %t %h %C %%`, plus the glibc/BSD `-` flag
/// (no padding, e.g. `%-d`). Unknown directives are copied verbatim.
fn strftime_impl(
  fmt : String,
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
  microsecond : Int,
  utcoffset : TimeDelta?,
  tzname : String?,
) -> String {
  let buf = StringBuilder()
  let chars = fmt.to_array()
  let n = chars.length()
  let wd = weekday_of(year, month, day)
  let yday = days_before_month(year, month) + day
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c != '%' || i + 1 >= n {
      buf.write_char(c)
      i += 1
      continue
    }
    let mut j = i + 1
    let nopad = chars[j] == '-'
    if nopad {
      j += 1
      if j >= n {
        buf.write_string("%-")
        break
      }
    }
    let num = (v : Int, width : Int) => {
      if nopad {
        v.to_string()
      } else {
        pad(v, width)
      }
    }
    let d = chars[j]
    match d {
      'a' => buf.write_string(day_abbrs[wd])
      'A' => buf.write_string(day_names[wd])
      'b' | 'h' => buf.write_string(month_abbrs[month])
      'B' => buf.write_string(month_names[month])
      'c' => buf.write_string(ctime_of(year, month, day, hour, minute, second))
      'C' => buf.write_string(num(year / 100, 2))
      'd' => buf.write_string(num(day, 2))
      'D' =>
        buf.write_string(
          "\{pad(month, 2)}/\{pad(day, 2)}/\{pad(year % 100, 2)}",
        )
      'e' =>
        buf.write_string(
          if nopad {
            day.to_string()
          } else {
            space_pad(day, 2)
          },
        )
      'f' => buf.write_string(pad(microsecond, 6))
      'F' => buf.write_string("\{pad(year, 4)}-\{pad(month, 2)}-\{pad(day, 2)}")
      'H' => buf.write_string(num(hour, 2))
      'I' => {
        let h = hour % 12
        buf.write_string(num(if h == 0 { 12 } else { h }, 2))
      }
      'j' => buf.write_string(num(yday, 3))
      'm' => buf.write_string(num(month, 2))
      'M' => buf.write_string(num(minute, 2))
      'n' => buf.write_char('\n')
      'p' => buf.write_string(if hour < 12 { "AM" } else { "PM" })
      'R' => buf.write_string("\{pad(hour, 2)}:\{pad(minute, 2)}")
      'S' => buf.write_string(num(second, 2))
      't' => buf.write_char('\t')
      'T' | 'X' =>
        buf.write_string("\{pad(hour, 2)}:\{pad(minute, 2)}:\{pad(second, 2)}")
      'u' => buf.write_string((wd + 1).to_string())
      'U' => {
        let sunday_wd = (wd + 1) % 7
        buf.write_string(num((yday - 1 + 7 - sunday_wd) / 7, 2))
      }
      'w' => buf.write_string(((wd + 1) % 7).to_string())
      'W' => buf.write_string(num((yday - 1 + 7 - wd) / 7, 2))
      'x' =>
        buf.write_string(
          "\{pad(month, 2)}/\{pad(day, 2)}/\{pad(year % 100, 2)}",
        )
      'y' => buf.write_string(num(year % 100, 2))
      'Y' => buf.write_string(year.to_string())
      'G' => buf.write_string(iso_calendar_of(year, month, day).0.to_string())
      'V' => buf.write_string(num(iso_calendar_of(year, month, day).1, 2))
      'z' => buf.write_string(format_utcoffset(utcoffset, sep=""))
      'Z' => buf.write_string(tzname.unwrap_or(""))
      '%' => buf.write_char('%')
      _ => {
        buf.write_char('%')
        if nopad {
          buf.write_char('-')
        }
        buf.write_char(d)
      }
    }
    i = j + 1
  }
  buf.to_string()
}

///|
/// `datetime.strftime(fmt)` (C locale).
pub fn DateTime::strftime(self : DateTime, fmt : String) -> String {
  strftime_impl(
    fmt,
    self.year,
    self.month,
    self.day,
    self.hour,
    self.minute,
    self.second,
    self.microsecond,
    self.utcoffset(),
    self.tzname(),
  )
}

///|
/// `date.strftime(fmt)` (C locale).
pub fn Date::strftime(self : Date, fmt : String) -> String {
  strftime_impl(fmt, self.year, self.month, self.day, 0, 0, 0, 0, None, None)
}

///|
/// `time.strftime(fmt)`; the date fields are 1900-01-01 like CPython.
pub fn Time::strftime(self : Time, fmt : String) -> String {
  strftime_impl(
    fmt,
    1900,
    1,
    1,
    self.hour,
    self.minute,
    self.second,
    self.microsecond,
    self.utcoffset(),
    self.tzname(),
  )
}
