#!/usr/bin/env python3
"""Generate rrule/corpus_data_wbtest.mbt: a differential corpus produced by
the reference python-dateutil implementation.

Run from the repo root (with .repos symlinked):
    python3 tools/gen_rrule_corpus.py

Each line of the corpus is one random case (tab-separated fields):

    kwargs  occurrences  str  roundtrip  queries

* kwargs: `name=value` pairs joined by `;` (see `parse_case` in
  rrule/corpus_wbtest.mbt). Lists are comma-separated (empty value = empty
  tuple); weekdays are `W` or `W:n`; datetimes are `YYYYMMDDTHHMMSS[Z]`
  (`Z` = tz.UTC).
* occurrences: the first <= N occurrences (`list(islice(rr, N))`) as
  datetimes, space-separated, followed by `!` if iteration raised; or
  `!new` if the constructor raised ValueError.
* str: `str(rr)` with newlines as `\\n`.
* roundtrip: first <= N occurrences of `rrulestr(str(rr))` (or `!`).
* queries: `before/after/between` results for a probe datetime (see
  `check_queries` in rrule/corpus_wbtest.mbt).

There are also rruleset cases (lines starting with `set`).
"""
import itertools
import os
import random
import signal
import subprocess
import sys
from datetime import datetime, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path[:0] = [os.path.join(ROOT, "tools/pyshim"),
                os.path.join(ROOT, ".repos/dateutil/src")]

from dateutil import tz  # noqa: E402
from dateutil.rrule import rrule, rruleset, rrulestr, weekday  # noqa: E402

N = 20
rnd = random.Random(20261001)
UTC = tz.UTC


class Timeout(Exception):
    pass


def on_alarm(signum, frame):
    raise Timeout()


signal.signal(signal.SIGALRM, on_alarm)


def fmt_dt(d):
    s = d.strftime("%Y%m%dT%H%M%S")
    off = d.utcoffset()
    if off is not None:
        s += "Z" if not off else "@%d" % int(off.total_seconds())
    return s


def rand_dt(aware):
    r = rnd.random()
    if r < 0.05:
        year = rnd.randint(9996, 9999)
    elif r < 0.1:
        year = rnd.randint(1, 3)
    else:
        year = rnd.randint(1990, 2030)
    month = rnd.randint(1, 12)
    day = rnd.randint(1, 28 if rnd.random() < 0.7 else 31)
    while True:
        try:
            d = datetime(year, month, day, rnd.randint(0, 23),
                         rnd.randint(0, 59), rnd.randint(0, 59))
            break
        except ValueError:
            day -= 1
    if rnd.random() < 0.3:
        d = d.replace(minute=0, second=0)
    return d.replace(tzinfo=UTC) if aware else d


def rand_ints(lo, hi, nonzero=True, k=None):
    k = k if k is not None else rnd.choice([0, 1, 1, 1, 2, 2, 3, 4])
    vals = []
    for _ in range(k):
        v = rnd.randint(lo, hi)
        if nonzero and v == 0:
            v = 1
        vals.append(v)
    return vals


def rand_case():
    kw = {}
    freq = rnd.randint(0, 6)
    aware = rnd.random() < 0.15
    kw["dtstart"] = rand_dt(aware)
    if rnd.random() < 0.5:
        kw["interval"] = rnd.choice([1, 2, 3, 4, 5, 7, 10, 13, 25, 60, 90])
    if rnd.random() < 0.3:
        kw["wkst"] = rnd.randint(0, 6)
    r = rnd.random()
    if r < 0.5:
        kw["count"] = rnd.randint(0, 30)
    elif r < 0.75:
        start = kw["dtstart"]
        delta = timedelta(seconds=rnd.choice([3600, 86400, 86400 * 40, 86400 * 400, 86400 * 4000]) * rnd.random())
        try:
            kw["until"] = start + delta
        except OverflowError:
            pass
        if rnd.random() < 0.05:
            # until/dtstart awareness mismatch -> ValueError
            kw["until"] = kw["until"].replace(tzinfo=None if aware else UTC)
    p = 0.22
    if rnd.random() < p:
        kw["bysetpos"] = rand_ints(-12, 12)
    if rnd.random() < p:
        kw["bymonth"] = rand_ints(1, 12, k=rnd.randint(1, 4))
    if rnd.random() < p:
        kw["bymonthday"] = rand_ints(-31, 31)
    if rnd.random() < p * 0.6:
        kw["byyearday"] = rand_ints(-366, 366)
    if rnd.random() < p * 0.5:
        kw["byeaster"] = rand_ints(-30, 30, nonzero=False)
    if rnd.random() < p * 0.6:
        kw["byweekno"] = rand_ints(-53, 53)
    if rnd.random() < p * 1.5:
        wds = []
        for _ in range(rnd.randint(0, 4)):
            w = rnd.randint(0, 6)
            if rnd.random() < 0.4:
                n = rnd.choice([-5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 20, -20])
                wds.append((w, n))
            else:
                wds.append((w, None))
        kw["byweekday"] = wds
    if rnd.random() < p:
        kw["byhour"] = rand_ints(0, 23, nonzero=False)
    if rnd.random() < p:
        kw["byminute"] = rand_ints(0, 59, nonzero=False)
    if rnd.random() < p:
        kw["bysecond"] = rand_ints(0, 59, nonzero=False)
    return freq, kw


def to_py_kwargs(kw):
    out = dict(kw)
    if "byweekday" in out:
        out["byweekday"] = [weekday(w, n) if n is not None else weekday(w)
                            for (w, n) in out["byweekday"]]
    return out


def encode(freq, kw):
    parts = ["freq=%d" % freq]
    for k, v in kw.items():
        if k in ("dtstart", "until"):
            parts.append("%s=%s" % (k, fmt_dt(v)))
        elif k == "byweekday":
            parts.append("%s=%s" % (k, ",".join(
                "%d:%d" % (w, n) if n is not None else "%d" % w for (w, n) in v)))
        elif isinstance(v, list):
            parts.append("%s=%s" % (k, ",".join(str(x) for x in v)))
        else:
            parts.append("%s=%s" % (k, v))
    return ";".join(parts)


def take(it):
    out = []
    err = False
    try:
        for x in itertools.islice(it, N):
            out.append(fmt_dt(x))
    except (ValueError, IndexError, TypeError):
        err = True
    return " ".join(out) + (" !" if err and out else ("!" if err else ""))


def queries(rr, occ):
    # probe between the first and the last generated occurrence
    if len(occ) < 2:
        return "-"
    a, b = occ[0], occ[-1]
    span = (b - a).total_seconds()
    q = a + timedelta(seconds=int(span * rnd.random()))
    if rnd.random() < 0.3:
        q = rnd.choice(occ)
    q2 = q + timedelta(seconds=int((b - q).total_seconds() * rnd.random()))
    res = []
    for f in (lambda: rr.before(q), lambda: rr.before(q, inc=True),
              lambda: rr.after(q), lambda: rr.after(q, inc=True)):
        r = f()
        res.append(fmt_dt(r) if r is not None else "None")
    for inc in (False, True):
        res.append(",".join(fmt_dt(x) for x in rr.between(q, q2, inc=inc)))
    return "%s %s %s" % (fmt_dt(q), fmt_dt(q2), " ".join(r or "-" for r in res))


def rule_case():
    freq, kw = rand_case()
    line = [encode(freq, kw)]
    signal.setitimer(signal.ITIMER_REAL, 0.5)
    try:
        try:
            rr = rrule(freq, **to_py_kwargs(kw))
        except ValueError:
            return "\t".join(line + ["!new", "-", "-", "-"])
        occ_s = take(iter(rr))
        line.append(occ_s)
        line.append(str(rr).replace("\n", "\\n"))
        try:
            rt = take(iter(rrulestr(str(rr))))
        except (ValueError, IndexError, TypeError):
            rt = "!"
        line.append(rt)
        occ = list(itertools.islice(iter(rr), N)) if not occ_s.endswith("!") else []
        try:
            line.append(queries(rr, occ) if len(occ) == N else "-")
        except (ValueError, IndexError, TypeError):
            line.append("-")
        signal.setitimer(signal.ITIMER_REAL, 0)
        return "\t".join(line)
    except Timeout:
        return None
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


def set_case():
    rules = []
    exrules = []
    aware = rnd.random() < 0.15
    for lst, k in ((rules, rnd.randint(0, 3)), (exrules, rnd.choice([0, 0, 1, 2]))):
        for _ in range(k):
            while True:
                freq, kw = rand_case()
                kw.pop("until", None)
                kw["count"] = rnd.randint(1, 15)
                kw["dtstart"] = rand_dt(aware).replace(year=rnd.randint(1997, 1999))
                kw["dtstart"] = kw["dtstart"].replace(tzinfo=UTC if aware else None)
                try:
                    rrule(freq, **to_py_kwargs(kw))
                    break
                except ValueError:
                    pass
            lst.append((freq, kw))
    rdates = [rand_dt(aware).replace(year=rnd.randint(1997, 1999)) for _ in range(rnd.randint(0, 5))]
    exdates = [rand_dt(aware).replace(year=rnd.randint(1997, 1999)) for _ in range(rnd.randint(0, 3))]
    # make some exdates hit
    signal.setitimer(signal.ITIMER_REAL, 0.5)
    try:
        s = rruleset()
        for f, kw in rules:
            s.rrule(rrule(f, **to_py_kwargs(kw)))
        for f, kw in exrules:
            s.exrule(rrule(f, **to_py_kwargs(kw)))
        for d in rdates:
            s.rdate(d)
        allocc = list(itertools.islice(iter(s), 40))
        if allocc and rnd.random() < 0.7:
            exdates.append(rnd.choice(allocc))
            rdates.append(rnd.choice(allocc))
        s = rruleset()
        for f, kw in rules:
            s.rrule(rrule(f, **to_py_kwargs(kw)))
        for f, kw in exrules:
            s.exrule(rrule(f, **to_py_kwargs(kw)))
        for d in rdates:
            s.rdate(d)
        for d in exdates:
            s.exdate(d)
        occ = take(iter(s))
        enc = []
        for f, kw in rules:
            enc.append("R" + encode(f, kw))
        for f, kw in exrules:
            enc.append("X" + encode(f, kw))
        enc.append("D" + ",".join(fmt_dt(d) for d in rdates))
        enc.append("E" + ",".join(fmt_dt(d) for d in exdates))
        return "set\t" + "|".join(enc) + "\t" + occ
    except (Timeout, ValueError, IndexError, TypeError):
        return None
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


STR_CASES = [
    # (inputs without DTSTART get the `dtstart` flag, see main)
    ("RRULE:FREQ=DAILY;COUNT=3", ""),
    ("rrule:freq=daily;count=3;byday=mo,tu", "dtstart"),
    ("FREQ=WEEKLY;COUNT=5;BYDAY=+1MO,-1FR,TU(+2),WE(-1)", ""),
    ("FREQ=MONTHLY;COUNT=5;BYDAY=+1MO,-1FR,TU(+2),WE(-1)", ""),
    ("FREQ=MONTHLY;COUNT=5;BYDAY=1MO,+0FR", ""),
    ("FREQ=MONTHLY;COUNT=5;BYDAY=12", ""),
    ("FREQ=MONTHLY;COUNT=5;BYDAY=MO()", ""),
    ("FREQ=MONTHLY;COUNT=5;BYDAY=MO,", ""),
    ("FREQ=MONTHLY;COUNT= 5 ;BYMONTHDAY=1_0,-1", ""),
    ("FREQ=MONTHLY;COUNT=5;BYMONTHDAY=1__0", ""),
    ("FREQ=MONTHLY;COUNT=5;FOO=1", ""),
    ("FREQ=MONTHLY;COUNT=5;", ""),
    ("FREQ=SOMETIMES;COUNT=5", ""),
    ("COUNT=5", ""),
    ("FREQ=YEARLY;COUNT=3;WKST=SU;BYWEEKNO=1,-1;BYDAY=SU", ""),
    ("FREQ=YEARLY;WKST=XX;COUNT=3", ""),
    ("FREQ=YEARLY;UNTIL=20000101;BYEASTER=0,-2", ""),
    ("FREQ=YEARLY;UNTIL=20000101T120000Z;BYEASTER=0", ""),
    ("FREQ=YEARLY;UNTIL=garbage", ""),
    ("FREQ=DAILY;COUNT=3;BYSETPOS=0", ""),
    ("FREQ=HOURLY;INTERVAL=4;BYHOUR=7,11;COUNT=3", ""),
    ("RRULE:FREQ=DAILY:COUNT=3", ""),
    ("XRULE:FREQ=DAILY;COUNT=3", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=3", ""),
    ("DTSTART:20000101T000000Z\nRRULE:FREQ=DAILY;COUNT=3", ""),
    ("DTSTART:20000101T000000Z\nRRULE:FREQ=DAILY;COUNT=3", "ignoretz"),
    ("DTSTART:20000101T000000Z\nRRULE:FREQ=DAILY;UNTIL=20000103T000000Z", ""),
    ("DTSTART:20000101T000000Z\nRRULE:FREQ=DAILY;UNTIL=20000103T000000", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;UNTIL=20000103T000000Z", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;UNTIL=20000103T000000Z", "ignoretz"),
    ("DTSTART:20000101T000000", ""),
    ("DTSTART:20000101T000000\nRDATE:20000105T000000,20000104T000000", ""),
    ("DTSTART:20000101T000000\nRDATE;VALUE=DATE-TIME:20000105T000000", ""),
    ("DTSTART:20000101T000000\nRDATE;VALUE=DATE:20000105", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=5\nEXDATE;VALUE=DATE-TIME;VALUE=DATE:20000102T000000", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=5\nEXDATE;FOO=BAR:20000102T000000", ""),
    ("DTSTART;TZID=unknown/zone;VALUE=DATE:20000101\nRRULE:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART;TZID=UTC:20000101T000000\nRRULE:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART;tzid=UTC:20000101T000000\nRRULE:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART:20000101T000000\nRRULE;X=Y:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART:20000101T000000\nEXRULE;X=Y:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART:20000101T000000\nFOO:BAR", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=5\nEXRULE:FREQ=DAILY;INTERVAL=2;COUNT=5", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=2\nRRULE:FREQ=WEEKLY;COUNT=3", ""),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=3", "forceset"),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAILY;COUNT=3;INTERVAL=2", "compatible"),
    ("DTSTART:20000101T000000\nRRULE:FREQ=DAI\n LY;COUNT=3", "unfold"),
    ("DTSTART:20000101T000000\r\n\r\nRRULE:FREQ=DAILY;\r\n COUNT=3  \r\n", "unfold"),
    ("  DTSTART:20000101T000000   RRULE:FREQ=DAILY;COUNT=3  ", ""),
    ("   ", ""),
    ("", ""),
    ("FREQ=DAILY;COUNT=3", "dtstart"),
    ("DTSTART:1997-09-02T09:00:00\nRRULE:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART:1997-09-02T09:00:00+02:00\nRRULE:FREQ=DAILY;UNTIL=1997-09-04T00:00:00Z", ""),
    ("DTSTART:19970902T090000\nRRULE:FREQ=DAILY;UNTIL=1997-09-04", ""),
    ("DTSTART:19970902T090000\nRDATE:1997-09-10,1997-09-11T10:00\nEXDATE:19970910", ""),
    ("DTSTART;TZID=UTC:19970902T090000+0100\nRRULE:FREQ=DAILY;COUNT=2", ""),
    ("DTSTART:19970902T090000\nRRULE:FREQ=YEARLY;COUNT=3;INTERVAL=3;BYMONTH=3;BYWEEKDAY=TH;BYMONTHDAY=3;BYHOUR=3;BYMINUTE=3;BYSECOND=3", ""),
]


def str_case(s, flags):
    kw = {}
    for f in flags.split(","):
        if f == "dtstart":
            kw["dtstart"] = datetime(2001, 2, 3, 4, 5, 6)
        elif f:
            kw[f] = True
    try:
        r = rrulestr(s, **kw)
    except Exception as e:
        return "!" + ("ValueError" if isinstance(e, ValueError) else type(e).__name__)
    kind = "rule:" if isinstance(r, rrule) else "set:"
    return kind + take(iter(r))


def main():
    lines = []
    while len(lines) < 700:
        c = rule_case()
        if c is not None:
            lines.append(c)
            if len(lines) % 100 == 0:
                print("  %d rule cases" % len(lines), file=sys.stderr, flush=True)
    sets = []
    while len(sets) < 150:
        c = set_case()
        if c is not None:
            sets.append(c)
    strs = []
    for src, flags in STR_CASES:
        if "DTSTART" not in src.upper() and "dtstart" not in flags:
            # without a start the rule depends on the clock
            flags = ",".join(x for x in (flags, "dtstart") if x)
        strs.append("%s\t%s\t%s" % (src.replace("\n", "\\n").replace("\r", "\\r"),
                                       flags or "-", str_case(src, flags)))
    path = os.path.join(ROOT, "rrule/corpus_data_wbtest.mbt")
    with open(path, "w") as f:
        f.write("// Generated by tools/gen_rrule_corpus.py from python-dateutil; do not edit.\n\n")
        for name, data in (("rule_corpus", lines), ("set_corpus", sets), ("str_corpus", strs)):
            f.write("///|\nlet %s : String =\n" % name)
            for l in data:
                f.write("  #|%s\n" % l)
            f.write("\n")
    subprocess.run(["moon", "fmt"], cwd=ROOT, check=False)
    print("wrote %d rule cases, %d set cases" % (len(lines), len(sets)), file=sys.stderr)


if __name__ == "__main__":
    main()
