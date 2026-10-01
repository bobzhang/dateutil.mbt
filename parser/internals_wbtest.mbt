// Ported from dateutil tests/test_internals.py (the `_ymd` smoke test).

///|
fn dec(n : Int) -> Dec {
  { ip: n.to_int64(), frac: "", int_digits: 0, }
}

///|
fn raises(f : () -> Unit raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "test_internals::test_YMD_could_be_day" {
  let ymd = Ymd::new()
  ymd.append(Whole(2), label=LM)
  assert_true(ymd.mstridx is Some(_))
  assert_true(ymd.ystridx is None)
  assert_true(ymd.could_be_day(dec(4)))
  // Python passes -6; our Dec only models the tokenizer's non-negative
  // values, so check 0 instead.
  assert_false(ymd.could_be_day(dec(0)))
  assert_false(ymd.could_be_day(dec(32)))
  // Assumes leap year
  assert_true(ymd.could_be_day(dec(29)))
  ymd.append(Whole(1999))
  assert_true(ymd.ystridx is Some(_))
  assert_false(ymd.could_be_day(dec(29)))
  ymd.append(Whole(16), label=LD)
  assert_true(ymd.dstridx is Some(_))
  assert_false(ymd.could_be_day(dec(1)))
  let ymd = Ymd::new()
  ymd.append(Whole(1999))
  assert_true(ymd.could_be_day(dec(31)))
}

///|
test "Dec: exact fractional arithmetic" {
  let d = try! to_decimal("5.6")
  assert_eq(d.ip, 5L)
  assert_eq(try! d.frac60(), 36L)
  let d = try! to_decimal("10.0000")
  assert_false(d.has_frac())
  assert_true(d.le(10L))
  assert_false(d.gt(10L))
  let d = try! to_decimal("0.99999999999999999999999")
  assert_eq(try! d.frac60(), 59L)
  // Python's decimal context rounds to 28 significant digits
  let d = try! to_decimal("0.99999999999999999999999999999")
  assert_eq(try! d.frac60(), 60L)
  let d = try! to_decimal("0.0000000000000000000000000000000000001")
  assert_true(try! d.mod1_nonzero())
  assert_eq(try! d.frac60(), 0L)
  let d = try! to_decimal("12345678901234567890123456789")
  assert_true(raises(() => ignore(d.mod1_nonzero())))
  assert_true(raises(() => ignore(to_decimal("nan"))))
  assert_true(raises(() => ignore(to_decimal("1.e"))))
  let d = try! to_decimal("\u{663}\u{664}.\u{665}") // Arabic-Indic digits
  assert_eq(d.ip, 34L)
  assert_eq(d.frac, "5")
}

///|
test "py_str helpers" {
  assert_true(py_isalpha_char('я'))
  assert_true(py_isalpha_char('中'))
  assert_false(py_isalpha_char('1'))
  assert_true(py_isdigit_char('\u{b2}')) // superscript two
  assert_eq(py_decimal_value('\u{b2}'), -1)
  assert_eq(py_decimal_value('\u{ff15}'), 5) // fullwidth 5
  assert_true(py_isspace_char('\u{1c}'))
  assert_true(py_isspace_char('\u{3000}'))
  assert_eq(py_lower("СЕНТЯБРЬ"), "сентябрь")
  assert_eq(py_lower("ΟΔΟΣ"), "οδος")
  assert_eq(py_lower("ΟΔΟΣ ΣΑ"), "οδος σα")
  assert_eq(py_lower("\u{130}"), "i\u{307}")
  assert_eq(py_lower("中Σ"), "中σ")
  assert_eq(py_lower("Α'Σ'"), "α'ς'")
  assert_eq(py_lower("ΑΣ'Α"), "ασ'α")
  assert_eq(try! py_int(" +1_000 "), 1000L)
  assert_true(raises(() => ignore(py_int("1__0"))))
  assert_true(raises(() => ignore(py_int(""))))
  assert_true(py_float_ok("Infinity"))
  assert_true(py_float_ok("12.5"))
  assert_false(py_float_ok("1.e"))
  assert_eq(py_slice("𝟐𝟎𝟎𝟑", 1, end=3), "𝟎𝟎")
  assert_eq(py_len("𝟐𝟎𝟎𝟑"), 4)
}
