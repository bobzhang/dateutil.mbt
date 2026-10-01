///|
/// A set of recurrences (Python `rruleset`): the union of rules (`rrule`)
/// and dates (`rdate`), minus exclusion rules (`exrule`) and dates
/// (`exdate`). Occurrences are produced in order without duplicates.
pub struct RruleSet {
  priv base : Base
  priv rrules : Array[Rrule]
  priv rdates : Array[@datetime.DateTime]
  priv exrules : Array[Rrule]
  priv exdates : Array[@datetime.DateTime]
}

///|
/// Create an empty set (Python `rruleset(cache=False)`).
///
/// ```mbt check
/// test {
///   let set = @rrule.RruleSet::new()
///   set.rrule(
///     @rrule.Rrule::new(
///       Daily,
///       count=5,
///       dtstart=@datetime.DateTime::new(2024, 1, 1, hour=9),
///     ),
///   )
///   set.exdate(@datetime.DateTime::new(2024, 1, 3, hour=9))
///   set.rdate(@datetime.DateTime::new(2024, 1, 10, hour=9))
///   debug_inspect(set.to_array().map(d => d.day), content="[1, 2, 4, 5, 10]")
/// }
/// ```
pub fn RruleSet::new(cache? : Bool = false) -> RruleSet {
  let set : RruleSet = {
    base: Base::new(cache),
    rrules: [],
    rdates: [],
    exrules: [],
    exdates: [],
  }
  set.base.invalidate(set.raw_iter())
  set
}

///|
/// Include the given rule in the recurrence set generation.
pub fn RruleSet::rrule(self : RruleSet, rrule : Rrule) -> Unit {
  self.rrules.push(rrule)
  self.base.invalidate(self.raw_iter())
}

///|
/// Include the given datetime in the recurrence set generation.
pub fn RruleSet::rdate(self : RruleSet, rdate : @datetime.DateTime) -> Unit {
  self.rdates.push(rdate)
  self.base.invalidate(self.raw_iter())
}

///|
/// Exclude the occurrences of the given rule, even if some inclusive rule
/// or date matches them.
pub fn RruleSet::exrule(self : RruleSet, exrule : Rrule) -> Unit {
  self.exrules.push(exrule)
  self.base.invalidate(self.raw_iter())
}

///|
/// Exclude the given datetime, even if some inclusive rule or date matches
/// it.
pub fn RruleSet::exdate(self : RruleSet, exdate : @datetime.DateTime) -> Unit {
  self.exdates.push(exdate)
  self.base.invalidate(self.raw_iter())
}

///|
/// Python `rruleset._genitem`: a generator with its current value, kept in
/// a heap ordered by `dt`.
priv struct GenItem {
  mut dt : @datetime.DateTime
  gen : Gen
  genlist : Array[GenItem]
}

///|
/// Python `_genitem(genlist, gen)`: pushes itself onto `genlist` unless
/// `gen` is already exhausted.
fn GenItem::add(
  genlist : Array[GenItem],
  gen : Gen,
) -> Unit raise @datetime.DateTimeError {
  if gen.next() is Some(dt) {
    genlist.push({ dt, gen, genlist, })
  }
}

///|
fn gi_lt(a : GenItem, b : GenItem) -> Bool raise @datetime.DateTimeError {
  dt_lt(a.dt, b.dt)
}

///|
/// Python `_genitem.__next__`.
fn GenItem::advance(self : GenItem) -> Unit raise @datetime.DateTimeError {
  match self.gen.next() {
    Some(dt) => self.dt = dt
    None => {
      let genlist = self.genlist
      if physical_equal(genlist[0], self) {
        heappop(genlist)
      } else {
        // list.remove: first item identical or equal (by `dt`) to self
        for i, x in genlist {
          if physical_equal(x, self) || x.dt == self.dt {
            genlist.remove(i) |> ignore
            break
          }
        }
        heapify(genlist)
      }
    }
  }
}

// CPython `heapq` (same algorithm as the C accelerator), using `<` only.

///|
fn heap_siftdown(
  heap : Array[GenItem],
  startpos : Int,
  pos : Int,
) -> Unit raise @datetime.DateTimeError {
  let newitem = heap[pos]
  let mut pos = pos
  while pos > startpos {
    let parentpos = (pos - 1) >> 1
    let parent = heap[parentpos]
    if gi_lt(newitem, parent) {
      heap[pos] = parent
      pos = parentpos
      continue
    }
    break
  }
  heap[pos] = newitem
}

///|
fn heap_siftup(
  heap : Array[GenItem],
  pos : Int,
) -> Unit raise @datetime.DateTimeError {
  let endpos = heap.length()
  let startpos = pos
  let newitem = heap[pos]
  let mut pos = pos
  let mut childpos = 2 * pos + 1
  while childpos < endpos {
    let rightpos = childpos + 1
    if rightpos < endpos && !gi_lt(heap[childpos], heap[rightpos]) {
      childpos = rightpos
    }
    heap[pos] = heap[childpos]
    pos = childpos
    childpos = 2 * pos + 1
  }
  heap[pos] = newitem
  heap_siftdown(heap, startpos, pos)
}

///|
fn heapify(heap : Array[GenItem]) -> Unit raise @datetime.DateTimeError {
  let n = heap.length()
  for i = n / 2 - 1; i >= 0; i = i - 1 {
    heap_siftup(heap, i)
  }
}

///|
fn heappop(heap : Array[GenItem]) -> Unit raise @datetime.DateTimeError {
  let lastelt = heap.unsafe_pop()
  if !heap.is_empty() {
    heap[0] = lastelt
    heap_siftup(heap, 0)
  }
}

///|
fn heapreplace(
  heap : Array[GenItem],
  item : GenItem,
) -> Unit raise @datetime.DateTimeError {
  heap[0] = item
  heap_siftup(heap, 0)
}

///|
/// Python `rruleset._iter` as a resumable generator.
fn RruleSet::raw_iter(self : RruleSet) -> Gen {
  let mut started = false
  let rlist : Array[GenItem] = []
  let exlist : Array[GenItem] = []
  let mut lastdt : @datetime.DateTime? = None
  let mut total = 0
  let mut pending : GenItem? = None
  Gen::new(fn() -> @datetime.DateTime? raise @datetime.DateTimeError {
    if !started {
      started = true
      stable_sort(self.rdates, dt_lt)
      GenItem::add(rlist, Gen::from_array(self.rdates))
      let gens = self.rrules.map(r => r.gen())
      for g in gens {
        GenItem::add(rlist, g)
      }
      stable_sort(self.exdates, dt_lt)
      GenItem::add(exlist, Gen::from_array(self.exdates))
      let gens = self.exrules.map(r => r.gen())
      for g in gens {
        GenItem::add(exlist, g)
      }
      heapify(rlist)
      heapify(exlist)
    }
    if pending is Some(ritem) {
      pending = None
      ritem.advance()
      if !rlist.is_empty() && physical_equal(rlist[0], ritem) {
        heapreplace(rlist, ritem)
      }
    }
    while !rlist.is_empty() {
      let ritem = rlist[0]
      if lastdt is None || lastdt != Some(ritem.dt) {
        while !exlist.is_empty() && gi_lt(exlist[0], ritem) {
          let exitem = exlist[0]
          exitem.advance()
          if !exlist.is_empty() && physical_equal(exlist[0], exitem) {
            heapreplace(exlist, exitem)
          }
        }
        lastdt = Some(ritem.dt)
        if exlist.is_empty() || ritem.dt != exlist[0].dt {
          total += 1
          pending = Some(ritem)
          return Some(ritem.dt)
        }
      }
      ritem.advance()
      if !rlist.is_empty() && physical_equal(rlist[0], ritem) {
        heapreplace(rlist, ritem)
      }
    }
    self.base.len = Some(total)
    None
  })
}
