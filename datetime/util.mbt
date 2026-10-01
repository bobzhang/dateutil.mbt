///|
/// Zero-pad the decimal representation of a non-negative `n` to `width`.
fn pad(n : Int, width : Int) -> String {
  let s = n.abs().to_string()
  let body = if s.length() >= width {
    s
  } else {
    "0".repeat(width - s.length()) + s
  }
  if n < 0 {
    "-" + body
  } else {
    body
  }
}

///|
/// Python's `round()` for doubles: round half to even.
pub fn round_half_even(x : Double) -> Double {
  let f = x.floor()
  let diff = x - f
  if diff > 0.5 {
    f + 1.0
  } else if diff < 0.5 {
    f
  } else if (f * 0.5).floor() * 2.0 == f {
    f
  } else {
    f + 1.0
  }
}

///|
/// `math.modf`: returns `(fractional, integral)` parts, both with the sign of `x`.
fn modf(x : Double) -> (Double, Double) {
  let i = if x < 0.0 { (-x).floor() * -1.0 } else { x.floor() }
  (x - i, i)
}
