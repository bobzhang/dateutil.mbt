// Python float semantics needed by relativedelta: exact decimal expansion,
// `round(x, ndigits)`, `format(x, "+g")`, `divmod` and `int()`.

///|
/// Exact decimal expansion of a finite, non-zero `x`:
/// `|x| == n * 10^e` with `n` a positive integer.
fn exact_decimal(x : Double) -> (@bigint.BigInt, Int) {
  let bits = x.reinterpret_as_uint64()
  let exp_bits = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & ((1UL << 52) - 1UL)
  let (m0, e0) = if exp_bits == 0 {
    (frac, -1074)
  } else {
    (frac | (1UL << 52), exp_bits - 1075)
  }
  let mut m = m0
  let mut e = e0
  while m != 0UL && (m & 1UL) == 0UL {
    m = m >> 1
    e += 1
  }
  let big = @bigint.BigInt::from_uint64(m)
  if e >= 0 {
    (big << e, 0)
  } else {
    (big * pow5(-e), e)
  }
}

///|
fn pow5(k : Int) -> @bigint.BigInt {
  @bigint.BigInt::from_int(5).pow(@bigint.BigInt::from_int(k))
}

///|
fn pow10(k : Int) -> @bigint.BigInt {
  @bigint.BigInt::from_int(10).pow(@bigint.BigInt::from_int(k))
}

///|
/// Divide the non-negative integer `n` by `10^k`, rounding half to even
/// (exactly).
fn div_pow10_half_even(n : @bigint.BigInt, k : Int) -> @bigint.BigInt {
  if k <= 0 {
    return n
  }
  let p = pow10(k)
  let q = n / p
  let r = n % p
  let c = (r * @bigint.BigInt::from_int(2)).compare(p)
  let odd = !(q % @bigint.BigInt::from_int(2)).is_zero()
  if c > 0 || (c == 0 && odd) {
    q + @bigint.BigInt::from_int(1)
  } else {
    q
  }
}

///|
/// Python `round(x, ndigits)` for a float: correctly rounded (half to
/// even on the exact binary value), converted back to the nearest double.
fn py_round_ndigits(x : Double, ndigits : Int) -> Double {
  if x == 0.0 || x.is_nan() || x.is_inf() {
    return x
  }
  let (n, e) = exact_decimal(x)
  if e >= -ndigits {
    return x
  }
  let q = div_pow10_half_even(n, -ndigits - e)
  let sign = if x < 0.0 { "-" } else { "" }
  @string.parse_double("\{sign}\{q}e-\{ndigits}") catch {
    _ => abort("unreachable: invalid float literal")
  }
}

///|
/// Python `format(x, "+g")` (6 significant digits, trailing zeros removed).
fn py_format_plus_g(x : Double) -> String {
  if x.is_nan() {
    return "+nan"
  }
  let sign = if x < 0.0 || (x == 0.0 && 1.0 / x < 0.0) { "-" } else { "+" }
  if x.is_inf() {
    return "\{sign}inf"
  }
  if x == 0.0 {
    return "\{sign}0"
  }
  let precision = 6
  let (n, e) = exact_decimal(x)
  let s = n.to_string()
  let len = s.length()
  let mut exp10 = len - 1 + e
  let mut digits = s
  if len > precision {
    let qs = div_pow10_half_even(n, len - precision).to_string()
    if qs.length() > precision {
      // Rounding carried into a new leading digit (e.g. 999999.5 -> 1e+06).
      exp10 += 1
      digits = qs.view(end_offset=precision).to_owned()
    } else {
      digits = qs
    }
  }
  let mut end = digits.length()
  while end > 1 && digits[end - 1] == '0' {
    end -= 1
  }
  let digits = digits.view(end_offset=end).to_owned()
  let body = if exp10 >= -4 && exp10 < precision {
    if exp10 >= 0 {
      let int_len = exp10 + 1
      if digits.length() <= int_len {
        digits + "0".repeat(int_len - digits.length())
      } else {
        digits.view(end_offset=int_len).to_owned() +
        "." +
        digits.view(start_offset=int_len).to_owned()
      }
    } else {
      "0." + "0".repeat(-exp10 - 1) + digits
    }
  } else {
    let mantissa = if digits.length() > 1 {
      digits.view(end_offset=1).to_owned() +
      "." +
      digits.view(start_offset=1).to_owned()
    } else {
      digits
    }
    let esign = if exp10 < 0 { "-" } else { "+" }
    let eabs = exp10.abs()
    let estr = if eabs < 10 { "0\{eabs}" } else { "\{eabs}" }
    "\{mantissa}e\{esign}\{estr}"
  }
  sign + body
}

///|
/// Python `divmod(x, y)` for floats with `x >= 0` and `y > 0`
/// (CPython `float_divmod`).
fn py_divmod_nonneg(x : Double, y : Double) -> (Double, Double) {
  let m = x.mod(y)
  let div = (x - m) / y
  let m = if m == 0.0 { 0.0 } else { m }
  let floordiv = if div != 0.0 {
    let f = div.floor()
    if div - f > 0.5 {
      f + 1.0
    } else {
      f
    }
  } else {
    0.0
  }
  (floordiv, m)
}

///|
/// Python `int(copysign(1, x))` as a float.
fn py_sign(x : Double) -> Double {
  if x < 0.0 || (x == 0.0 && 1.0 / x < 0.0) {
    -1.0
  } else {
    1.0
  }
}

///|
/// Python `int(x)` for a float, kept as an (integral) float: raises like
/// Python for NaN and infinities. `-0.0` becomes `0.0`.
fn py_int_float(x : Double) -> Double raise @datetime.DateTimeError {
  if x.is_nan() {
    raise @datetime.ValueError("cannot convert float NaN to integer")
  }
  if x.is_inf() {
    raise @datetime.OverflowError("cannot convert float infinity to integer")
  }
  x.trunc() + 0.0
}

///|
/// Python `int(x)` for a float, as an `Int64`; `OverflowError` when the
/// value does not fit (Python ints are unbounded).
fn py_int64(x : Double) -> Int64 raise @datetime.DateTimeError {
  let t = py_int_float(x)
  if t >= 9.2e18 || t <= -9.2e18 {
    raise @datetime.OverflowError("Python int too large to convert to C int")
  }
  t.to_int64()
}

///|
/// Narrow an `Int64` to `Int`, raising `OverflowError` if it does not fit.
fn int64_to_int(x : Int64) -> Int raise @datetime.DateTimeError {
  if x > 2147483647L || x < -2147483648L {
    raise @datetime.OverflowError("Python int too large to convert to C int")
  }
  x.to_int()
}
