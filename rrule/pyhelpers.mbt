// Small helpers reproducing Python built-in semantics used by rrule.py.

///|
/// `sorted(set(xs))`.
fn uniq_sorted(xs : Array[Int]) -> Array[Int] {
  let ys = xs.copy()
  ys.sort()
  let out = []
  for i, y in ys {
    if i == 0 || ys[i - 1] != y {
      out.push(y)
    }
  }
  out
}

///|
/// `math.gcd` (always non-negative).
fn gcd(a : Int, b : Int) -> Int {
  let mut a = a.abs()
  let mut b = b.abs()
  while b != 0 {
    let t = a % b
    a = b
    b = t
  }
  a
}

///|
/// Python `seq[i]` index normalization; `None` means `IndexError`.
fn py_index(len : Int, i : Int) -> Int? {
  if i >= 0 {
    if i < len {
      Some(i)
    } else {
      None
    }
  } else if i + len >= 0 {
    Some(i + len)
  } else {
    None
  }
}

///|
fn index_error() -> @datetime.DateTimeError {
  @datetime.ValueError(
    // Python raises IndexError; mapped onto ValueError (see PORTING.md).
    "list index out of range",
  )
}

///|
/// Python `seq[start:stop:step]` (with `step != 0`; `None` = omitted).
fn[T] py_slice(
  xs : Array[T],
  start : Int?,
  stop : Int?,
  step : Int?,
) -> Array[T] raise @datetime.DateTimeError {
  let step = step.unwrap_or(1)
  if step == 0 {
    raise @datetime.ValueError("slice step cannot be zero")
  }
  let len = xs.length()
  fn adjust(v : Int?, default : Int) -> Int {
    match v {
      None => default
      Some(v) =>
        if v < 0 {
          let v = v + len
          if v < 0 {
            if step < 0 {
              -1
            } else {
              0
            }
          } else {
            v
          }
        } else if v >= len {
          if step < 0 {
            len - 1
          } else {
            len
          }
        } else {
          v
        }
    }
  }

  let out = []
  if step > 0 {
    let start = adjust(start, 0)
    let stop = adjust(stop, len)
    let mut i = start.to_int64()
    while i < stop.to_int64() {
      out.push(xs[i.to_int()])
      i += step.to_int64()
    }
  } else {
    let start = adjust(start, len - 1)
    let stop = adjust(stop, -1)
    let mut i = start.to_int64()
    while i > stop.to_int64() {
      out.push(xs[i.to_int()])
      i += step.to_int64()
    }
  }
  out
}

///|
/// Stable merge sort with a raising "less than" (Python `list.sort()` only
/// uses `<` and is stable).
fn[T] stable_sort(
  xs : Array[T],
  lt : (T, T) -> Bool raise @datetime.DateTimeError,
) -> Unit raise @datetime.DateTimeError {
  let n = xs.length()
  if n < 2 {
    return
  }
  let mut src = xs.copy()
  let mut dst = xs.copy()
  let mut width = 1
  while width < n {
    for lo = 0; lo < n; lo = lo + 2 * width {
      let mid = (lo + width).min(n)
      let hi = (lo + 2 * width).min(n)
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while i < mid && j < hi {
        // take from the right run only if strictly smaller (stability)
        if lt(src[j], src[i]) {
          dst[k] = src[j]
          j += 1
        } else {
          dst[k] = src[i]
          i += 1
        }
        k += 1
      }
      while i < mid {
        dst[k] = src[i]
        i += 1
        k += 1
      }
      while j < hi {
        dst[k] = src[j]
        j += 1
        k += 1
      }
    }
    let t = src
    src = dst
    dst = t
    width *= 2
  }
  for i in 0..<n {
    xs[i] = src[i]
  }
}

///|
/// Python `a < b` for datetimes (raises `TypeError` for naive vs aware).
fn dt_lt(
  a : @datetime.DateTime,
  b : @datetime.DateTime,
) -> Bool raise @datetime.DateTimeError {
  a.checked_compare(b) < 0
}
