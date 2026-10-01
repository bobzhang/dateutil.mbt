// White-box ports of upstream tests that inspect the private `_cache`.

///|
test "RRuleTest.testCachePostInternal" {
  let rr = Rrule::new(
    Daily,
    count=15,
    cache=true,
    dtstart=@datetime.DateTime::new(1997, 9, 2, hour=9),
  )
  for _ in rr.iter() {

  }
  let expected = []
  for d in 2..<=16 {
    expected.push(@datetime.DateTime::new(1997, 9, d, hour=9))
  }
  assert_eq(rr.base.cache, Some(expected))
}

///|
test "RRuleSetTest.testSetCachePostInternal" {
  let rrset = RruleSet::new(cache=true)
  let start = @datetime.DateTime::new(1997, 9, 2, hour=9)
  rrset.rrule(Rrule::new(Yearly, count=2, byweekday=[tu], dtstart=start))
  rrset.rrule(Rrule::new(Yearly, count=1, byweekday=[th], dtstart=start))
  for _ in rrset.iter() {

  }
  assert_eq(
    rrset.base.cache,
    Some([
      @datetime.DateTime::new(1997, 9, 2, hour=9),
      @datetime.DateTime::new(1997, 9, 4, hour=9),
      @datetime.DateTime::new(1997, 9, 9, hour=9),
    ]),
  )
}
