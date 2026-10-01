// Exact integer helpers (Python `int` semantics) used where CPython relies
// on arbitrary precision: float -> timedelta conversion and float
// multiplication.

///|
fn big(n : Int64) -> @bigint.BigInt {
  @bigint.BigInt::from_int64(n)
}

///|
/// Python `divmod` (floor semantics) on big integers.
fn big_divmod(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt) {
  let q = a / b
  let r = a - q * b
  if !r.is_zero() && (r.compare_int(0) < 0) != (b.compare_int(0) < 0) {
    (q - big(1L), r + b)
  } else {
    (q, r)
  }
}

///|
/// CPython `_divide_and_round`: `a / b` rounded half to even.
fn big_divide_and_round(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> @bigint.BigInt {
  let (q, r) = big_divmod(a, b)
  let r2 = r * big(2L)
  let greater_than_half = if b.compare_int(0) > 0 {
    r2.compare(b) > 0
  } else {
    r2.compare(b) < 0
  }
  let q_odd = !(q % big(2L)).is_zero()
  if greater_than_half || (r2 == b && q_odd) {
    q + big(1L)
  } else {
    q
  }
}

///|
/// `float.as_integer_ratio()` for a finite double (not reduced; the
/// denominator is a power of two).
fn as_integer_ratio(x : Double) -> (@bigint.BigInt, @bigint.BigInt) {
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exp = ((bits >> 52) & 0x7ffUL).to_int()
  let frac = bits & 0xfffffffffffffUL
  let (mant, e) = if exp == 0 {
    (frac, -1074)
  } else {
    (frac | 0x10000000000000UL, exp - 1075)
  }
  let m = @bigint.BigInt::from_uint64(mant)
  let m = if negative { -m } else { m }
  if e >= 0 {
    (m.shl(e), big(1L))
  } else {
    (m, big(1L).shl(-e))
  }
}

///|
/// Exact conversion of an integral (or truncated) double to a big integer.
fn double_trunc_to_big(x : Double) -> @bigint.BigInt {
  let (a, b) = as_integer_ratio(x)
  // truncate toward zero
  a / b
}

///|
/// Total microseconds as a big integer (exact for the whole range).
fn TimeDelta::to_big_us(self : TimeDelta) -> @bigint.BigInt {
  (big(self.days.to_int64()) * big(86400L) + big(self.seconds.to_int64())) *
  big(1000000L) +
  big(self.microseconds.to_int64())
}

///|
/// Build a timedelta from big days/seconds/microseconds components.
fn TimeDelta::from_big(
  d : @bigint.BigInt,
  s : @bigint.BigInt,
  us : @bigint.BigInt,
) -> TimeDelta raise DateTimeError {
  let (carry, us) = big_divmod(us, big(1000000L))
  let (carry, s) = big_divmod(s + carry, big(86400L))
  let d = d + carry
  if d.compare_int(999999999) > 0 || d.compare_int(-999999999) < 0 {
    raise OverflowError("days=\{d}; must have magnitude <= 999999999")
  }
  { days: d.to_int(), seconds: s.to_int(), microseconds: us.to_int(), }
}
