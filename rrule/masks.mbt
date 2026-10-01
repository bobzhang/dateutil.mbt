// Static per-year masks (Python module-level `M366MASK` etc.). Every mask
// is 7 days longer than the year to handle cross-year weekly periods.

///|
let month_lengths_366 : FixedArray[Int] = [
  31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
]

///|
/// Build `(month mask, month-day mask, negative month-day mask)` for a year
/// with the given February length.
fn build_masks(
  feb : Int,
) -> (FixedArray[Int], FixedArray[Int], FixedArray[Int]) {
  let mmask = []
  let mday = []
  let nmday = []
  for m in 0..<12 {
    let len = if m == 1 { feb } else { month_lengths_366[m] }
    for d in 1..<=len {
      mmask.push(m + 1)
      mday.push(d)
      nmday.push(d - len - 1)
    }
  }
  // 7 extra days of next January
  for d in 1..<=7 {
    mmask.push(1)
    mday.push(d)
    nmday.push(d - 32)
  }
  (
    FixedArray::from_array(mmask),
    FixedArray::from_array(mday),
    FixedArray::from_array(nmday),
  )
}

///|
let masks_366 : (FixedArray[Int], FixedArray[Int], FixedArray[Int]) = build_masks(
  29,
)

///|
let masks_365 : (FixedArray[Int], FixedArray[Int], FixedArray[Int]) = build_masks(
  28,
)

///|
let m366range : FixedArray[Int] = [
  0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366,
]

///|
let m365range : FixedArray[Int] = [
  0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365,
]

///|
/// Length of Python's `WDAYMASK` (`[0..6] * 55`).
let wdaymask_len : Int = 385
