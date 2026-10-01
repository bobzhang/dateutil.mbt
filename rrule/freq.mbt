///|
/// Recurrence frequency (Python `YEARLY` .. `SECONDLY`, integers 0..6).
/// The derived ordering matches the Python integer ordering.
pub(all) enum Freq {
  Yearly
  Monthly
  Weekly
  Daily
  Hourly
  Minutely
  Secondly
} derive(Eq, Compare, Hash, Debug)

///|
/// The Python integer value (`YEARLY == 0` .. `SECONDLY == 6`).
pub fn Freq::to_int(self : Freq) -> Int {
  match self {
    Yearly => 0
    Monthly => 1
    Weekly => 2
    Daily => 3
    Hourly => 4
    Minutely => 5
    Secondly => 6
  }
}

///|
/// Inverse of `to_int`; raises `ValueError` outside `0..=6`.
pub fn Freq::from_int(i : Int) -> Freq raise @datetime.DateTimeError {
  match i {
    0 => Yearly
    1 => Monthly
    2 => Weekly
    3 => Daily
    4 => Hourly
    5 => Minutely
    6 => Secondly
    _ => raise @datetime.ValueError("invalid frequency: \{i}")
  }
}

///|
/// The RFC 5545 name (`FREQNAMES`), e.g. `YEARLY`.
pub impl Show for Freq with fn output(self, logger) {
  logger.write_string(
    match self {
      Yearly => "YEARLY"
      Monthly => "MONTHLY"
      Weekly => "WEEKLY"
      Daily => "DAILY"
      Hourly => "HOURLY"
      Minutely => "MINUTELY"
      Secondly => "SECONDLY"
    },
  )
}

///|
/// Parse an RFC 5545 frequency name (upper case), as `rrulestr` does.
fn Freq::from_name(name : String) -> Freq? {
  match name {
    "YEARLY" => Some(Yearly)
    "MONTHLY" => Some(Monthly)
    "WEEKLY" => Some(Weekly)
    "DAILY" => Some(Daily)
    "HOURLY" => Some(Hourly)
    "MINUTELY" => Some(Minutely)
    "SECONDLY" => Some(Secondly)
    _ => None
  }
}

///|
pub extend Freq with Show::{to_string, output}
