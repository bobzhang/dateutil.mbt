#!/usr/bin/env python3
"""Generate internal/tzdata/corpus_data_test.mbt.

Differential corpus for the pure TZif / POSIX-TZ engine used for system
local time on the wasm, wasm-gc and js backends.

* Zone records: real TZif files from the system zoneinfo database are
  embedded (base64) so the MoonBit tests are deterministic. The expected
  local time types come from CPython ``time.localtime`` run with
  ``os.environ['TZ'] = <zone>; time.tzset()`` against the same files.
* POSIX records: ``time.localtime`` under ``TZ=<string>`` where the C
  library implements the syntax; for RFC 9636 extensions the host libc
  lacks (negative or >24h rule times, on macOS) the reference is CPython's
  ``zoneinfo`` TZ-string evaluator. Each record names its reference.

Usage: python3 tools/gen_tzdata_corpus.py > internal/tzdata/corpus_data_test.mbt
"""

import base64
import calendar
import os
import struct
import sys
import time
from zoneinfo import _zoneinfo

ZONEINFO = "/usr/share/zoneinfo"

ZONES = [
    "America/New_York",  # footer needed after 2037
    "Europe/London",  # 1941 double summer time (BST in winter)
    "Australia/Sydney",  # southern hemisphere
    "Europe/Paris",  # sub-minute LMT/PMT offsets before 1911
    "Africa/Casablanca",  # negative DST, transitions to 2087, odd footer
    "Europe/Dublin",  # negative DST (winter time is "DST")
    "Asia/Shanghai",  # fixed footer after 1991
]


def libc_type(tz, t):
    os.environ["TZ"] = tz
    time.tzset()
    lt = time.localtime(t)
    return (lt.tm_gmtoff, lt.tm_isdst, lt.tm_zone)


def zoneinfo_type(tzstr, t):
    rule = _zoneinfo._parse_tz_str(tzstr)
    if isinstance(rule, _zoneinfo._ttinfo):
        tti = rule
    else:
        year = time.gmtime(t).tm_year
        tti, _fold = rule.get_trans_info_fromutc(t, year)
    off = int(tti.utcoff.total_seconds())
    return (off, 1 if tti.dstoff else 0, tti.tzname)


def tzif_transitions(data):
    """64-bit transition times of a v2+ TZif file."""
    cnt = struct.unpack(">6l", data[20:44])
    isut, isstd, leap, timecnt, typecnt, charcnt = cnt
    l1 = timecnt * 5 + typecnt * 6 + charcnt + leap * 8 + isstd + isut
    h2 = 44 + l1
    timecnt2 = struct.unpack(">6l", data[h2 + 20 : h2 + 44])[3]
    return list(struct.unpack(">%dq" % timecnt2, data[h2 + 44 : h2 + 44 + 8 * timecnt2]))


def scan_changes(fn, start, end, step=3600):
    """Exact instants in [start, end) where fn(t) changes."""
    out = []
    prev = fn(start)
    t = start
    while t < end:
        nt = min(t + step, end)
        cur = fn(nt)
        if cur != prev:
            lo, hi = t, nt
            while hi - lo > 1:
                mid = (lo + hi) // 2
                if fn(mid) == prev:
                    lo = mid
                else:
                    hi = mid
            out.append(hi)
            prev = cur
        t = nt
    return out


def year_start(y):
    return calendar.timegm((y, 1, 1, 0, 0, 0))


FIXED_TIMES = [
    -(2**36),
    -(10**10),
    -2208988800,  # 1900-01-01
    -1,
    0,
    2**31 - 1,
    2**31,
    2**32,
    10**10,
    2**36,
]


def sample_times(transitions, fn):
    ts = set(FIXED_TIMES)
    for tr in transitions:
        ts.update((tr - 1, tr))
    # footer era: exact transitions in a few years past the data, and far out
    for y in (2037, 2038, 2039, 2040, 2087, 2088, 2100, 2401):
        for tr in scan_changes(fn, year_start(y), year_start(y + 1)):
            ts.update((tr - 1, tr))
        ts.add(year_start(y))
        ts.add(year_start(y) - 1)
    return sorted(ts)


POSIX = [
    "EST5EDT,M3.2.0/2,M11.1.0/2",
    "EST+5EDT,M3.2.0,M11.1.0",
    "CST6CDT,J60/2,J300/2",  # Jn skips Feb 29
    "CST6CDT,59/2,299/2",  # n counts Feb 29
    "AEST-10AEDT,M10.1.0,M4.1.0/3",  # southern hemisphere
    "NZST-12NZDT,M9.5.0,M4.1.0/3",
    "IST-1GMT0,M10.5.0,M3.5.0/1",  # Dublin: negative DST
    "<+0330>-3:30<+0430>,J79/24,J263/24",  # quoted, 24:00
    "<-03>3<-02>,M3.5.0/-2,M10.5.0/-1",  # negative times
    "EST5EDT,M3.2.0/-1:30,M11.1.0/26",  # negative, >24h
    "<-01>1<+00>,M3.5.0/0,M10.5.0/1",
    "<+0545>-5:45",
    "JST-9",
    "UTC0",
    "<-1230>12:30",
    "HST10HDT9:30:15,M4.1.0/2:30:45,M10.5.0/1:15",  # seconds
    "XXX3YYY,M3.1.0/167,M10.1.0/-167",  # +-167h rule times
]


def libc_accepts(s):
    return libc_type(s, 10**9)[2] != "UTC" or s.startswith("UTC")


def posix_reference(s, t):
    """(type, reference name) for TZ string s at t, or (None, None).

    libc (CPython time.localtime) where it implements the string -- macOS
    libc (old tzcode) applies POSIX rules only after 1970 and rejects
    negative or >24h rule times; zoneinfo otherwise, except for zero-based
    ``n`` rules, which zoneinfo evaluates one day early."""
    zero_based = any(part[:1].isdigit() for part in s.split(",")[1:])
    if libc_accepts(s) and (t >= 31536000 or "," not in s):
        lc = libc_type(s, t)
        if not zero_based:
            zi = zoneinfo_type(s, t)
            if zi != lc:
                print("libc/zoneinfo disagree: %r %d %r %r" % (s, t, lc, zi), file=sys.stderr)
        return lc, "libc"
    if zero_based:
        return None, None
    return zoneinfo_type(s, t), "zoneinfo"

POSIX_TIMES = [
    -(10**10),
    -2208988800,
    0,
    951782400,  # 2000-02-29
    2**31,
    10**10,
]


def posix_times(fn):
    ts = set(POSIX_TIMES)
    for y in (1950, 2000, 2023, 2024, 2100):
        for tr in scan_changes(fn, year_start(y) - 86400 * 8, year_start(y + 1) + 86400 * 8):
            ts.update((tr - 1, tr))
        ts.update((year_start(y) - 1, year_start(y)))
    return sorted(ts)


def mbt_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    out = []
    w = out.append
    w("// Generated by tools/gen_tzdata_corpus.py -- DO NOT EDIT.")
    w("// TZif files from the system zoneinfo database (tzdata %s) and" % open(os.path.join(ZONEINFO, "+VERSION")).read().strip() if os.path.exists(os.path.join(ZONEINFO, "+VERSION")) else "// TZif files from the system zoneinfo database and")
    w("// local time types from CPython time.localtime (or zoneinfo, see records).")
    w("")
    w("///|")
    w("let zone_files : Map[String, String] = {")
    for z in ZONES:
        data = open(os.path.join(ZONEINFO, z), "rb").read()
        w("  %s: %s," % (mbt_str(z), mbt_str(base64.b64encode(data).decode())))
    w("}")
    w("")
    w("///|")
    w("/// zone|t|offset|isdst|abbr")
    w("let zone_corpus : Array[String] = [")
    for z in ZONES:
        data = open(os.path.join(ZONEINFO, z), "rb").read()
        fn = lambda t, z=z: libc_type(z, t)
        for t in sample_times(tzif_transitions(data), fn):
            off, isdst, abbr = fn(t)
            w("  %s," % mbt_str("%s|%d|%d|%d|%s" % (z, t, off, isdst, abbr)))
    w("]")
    w("")
    w("///|")
    w("/// tz|t|offset|isdst|abbr|reference")
    w("let posix_corpus : Array[String] = [")
    for s in POSIX:
        fn = lambda t, s=s: posix_reference(s, t)[0]
        for t in posix_times(fn):
            ty, ref = posix_reference(s, t)
            if ty is None:
                continue
            off, isdst, abbr = ty
            w("  %s," % mbt_str("%s|%d|%d|%d|%s|%s" % (s, t, off, isdst, abbr, ref)))
    w("]")
    print("\n".join(out))


if __name__ == "__main__":
    main()
