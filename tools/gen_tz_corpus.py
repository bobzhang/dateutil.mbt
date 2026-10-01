"""Generate tz test data from the reference python-dateutil.

Writes:
  tz/zone_data_test.mbt   base64 TZif data (system zoneinfo + upstream
                          test_tz.py constants), so tzfile tests run on
                          every backend
  tz/diff_corpus_test.mbt differential records (UTC->local conversions and
                          wall-time queries around transitions) computed by
                          dateutil from exactly those bytes, plus tzstr zones
  tz/diff_corpus_tzlocal_test.mbt
                          the same for tzlocal() under POSIX TZ strings

Run (from the repo root, with .repos symlinked):
  PYTHONPATH=tools/pyshim:.repos/dateutil/src:.repos/dateutil \
    python3 tools/gen_tz_corpus.py
"""
import base64
import io
import os
import sys
import time
import warnings
from datetime import datetime, timedelta

warnings.simplefilter("ignore")

from dateutil import tz  # noqa: E402

sys.path.insert(0, ".repos/dateutil")
from tests import test_tz  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZONEINFO = "/usr/share/zoneinfo"

SYSTEM_ZONES = [
    "America/New_York", "US/Eastern", "America/Toronto", "Australia/Sydney",
    "Australia/Canberra", "Europe/London", "Portugal", "Europe/Minsk",
    "Pacific/Apia", "Europe/Kiev", "Pacific/Kiritimati", "Africa/Monrovia",
    "Europe/Dublin", "Australia/Lord_Howe", "Antarctica/Troll",
    "Asia/Kolkata", "America/Sao_Paulo", "Africa/Casablanca",
    "Pacific/Chatham", "America/St_Johns", "Asia/Tehran", "Europe/Moscow",
    "UTC", "EST5EDT",
]

UPSTREAM = {
    "upstream:TZFILE_EST5EDT": test_tz.TZFILE_EST5EDT,
    "upstream:EUROPE_HELSINKI": test_tz.EUROPE_HELSINKI,
    "upstream:NEW_YORK": test_tz.NEW_YORK,
}

TZSTRS = [
    "EST5EDT",
    "EST+5EDT,M3.2.0/2,M11.1.0/2",
    "AEST-10AEDT,M10.1.0/2,M4.1.0/3",
    "GMT0BST,M3.5.0,M10.5.0",
    "IST-2IDT,M3.4.4/26,M10.5.0",
    "WART4WARST,J1/0,J365/25",
    "WGT3WGST,M3.5.0/2,M10.5.0/1",
    "EST5EDT4,M4.1.0/02:00:00,M10-5-0/02:00",
    "EST5EDT4,95/02:00:00,298/02:00",
    "EST5EDT4,J96/02:00:00,J299/02",
    "EST5EDT,5,4,0,7200,11,-3,0,7200,-3600",
    "EST5EDT,5,-4,0,7200,11,3,0,7200",
    "NZST-12NZDT,M9.5.0,M4.1.0/3",
    "IRST-3:30",
    "UTC-3",
    "GMT+2",
    "JST-9",
    "CET-1CEST,M3.5.0,M10.5.0/3",
    "AAA3BBB2,M1.1.0/0,M12.5.6/23",
]

# POSIX strings understood identically by libc and by dateutil's tzstr;
# used for tzlocal (native only), where TZ is set in the environment.
TZLOCAL_STRS = [
    "EST+5EDT,M3.2.0/2,M11.1.0/2",
    "AEST-10AEDT,M10.1.0/2,M4.1.0/3",
    "GMT0BST,M3.5.0,M10.5.0",
    "UTC",
    "JST-9",
]

EPOCH = datetime(1970, 1, 1)


def iso(dt):
    return dt.replace(tzinfo=None).isoformat()


def secs(td):
    if td is None:
        return "None"
    return str(int(td.total_seconds()))


def name(s):
    return "None" if s is None else s


def from_ts(t):
    return EPOCH + timedelta(seconds=t)


def utc_record(key, z, dt_utc):
    try:
        return _utc_record(key, z, dt_utc)
    except (OverflowError, ValueError):
        return None


def _utc_record(key, z, dt_utc):
    loc = dt_utc.replace(tzinfo=tz.UTC).astimezone(z)
    return "|".join(["F", key, iso(dt_utc), iso(loc), str(loc.fold),
                     secs(loc.utcoffset()), secs(loc.dst()),
                     name(loc.tzname())])


def wall_record(key, z, wall, fold):
    try:
        return _wall_record(key, z, wall, fold)
    except (OverflowError, ValueError):
        return None


def _wall_record(key, z, wall, fold):
    dt = tz.enfold(wall.replace(tzinfo=z), fold=fold)
    amb = z.is_ambiguous(dt)
    exists = tz.datetime_exists(dt)
    damb = tz.datetime_ambiguous(dt)
    back = dt.astimezone(tz.UTC).replace(tzinfo=None)
    res = tz.resolve_imaginary(dt)
    return "|".join(["W", key, iso(wall), str(fold), secs(dt.utcoffset()),
                     secs(dt.dst()), name(dt.tzname()), str(int(amb)),
                     str(int(exists)), str(int(damb)), iso(back),
                     iso(res) + "/" + str(res.fold)])


def pick(seq, n):
    if len(seq) <= n:
        return list(range(len(seq)))
    step = (len(seq) - 1) / (n - 1)
    return sorted({round(i * step) for i in range(n)})


def tzfile_records(key, z):
    out = []
    utcs = z._trans_list_utc
    walls = z._trans_list
    extra = [datetime(1800, 1, 1), datetime(1900, 1, 1, 12),
             datetime(1950, 6, 15), datetime(2040, 1, 1),
             datetime(2040, 7, 1), datetime(2100, 1, 1),
             datetime(9999, 12, 30)]
    for e in extra:
        out.append(utc_record(key, z, e))
        out.append(wall_record(key, z, e, 0))
    for i in pick(utcs, 5):
        t = utcs[i]
        if t < -2**31 + 7200 or t > 2**31 - 7200:
            continue
        for d in (-1, 0, 1799, 3600):
            out.append(utc_record(key, z, from_ts(t + d)))
        w = walls[i]
        for d in (-3600, -1, 0, 1800, 3599, 5400):
            for fold in (0, 1):
                out.append(wall_record(key, z, from_ts(w + d), fold))
    return out


def tzstr_records(key, z):
    out = []
    for e in (datetime(1, 1, 2), datetime(1900, 1, 1), datetime(9999, 12, 30)):
        out.append(utc_record(key, z, e))
        out.append(wall_record(key, z, e, 0))
    for year in (2003, 2038):
        trans = z.transitions(year)
        if trans is None:
            out.append(utc_record(key, z, datetime(year, 6, 1)))
            out.append(wall_record(key, z, datetime(year, 6, 1), 1))
            continue
        for t_std in trans:
            t_utc = t_std - z._std_offset
            for d in (-1, 0, 1799, 3600):
                out.append(utc_record(key, z, t_utc + timedelta(seconds=d)))
            for d in (-3600, -1, 0, 1800, 3599, 5400):
                for fold in (0, 1):
                    out.append(wall_record(
                        key, z, t_std + timedelta(seconds=d), fold))
    return out


def tzlocal_records(tzvar):
    os.environ["TZ"] = tzvar
    time.tzset()
    z = tz.tzlocal()
    key = "L:" + tzvar
    out = []
    years = (2011, 2024)
    ref = tz.tzstr(tzvar, posix_offset=True) if tzvar != "UTC" else tz.UTC
    for year in years:
        trans = ref.transitions(year) if hasattr(ref, "transitions") else None
        pivots = []
        if trans:
            pivots = [t - ref._std_offset for t in trans]
        else:
            pivots = [datetime(year, 6, 1)]
        for p in pivots:
            for d in (-1, 0, 1799, 3600):
                out.append(utc_record(key, z, p + timedelta(seconds=d)))
            wall = p + getattr(ref, "_std_offset", timedelta(0))
            for d in (-3600, -1, 0, 1800, 3599, 5400):
                for fold in (0, 1):
                    out.append(wall_record(
                        key, z, wall + timedelta(seconds=d), fold))
    return out


PARSE_STRS = TZSTRS + [
    "", "UTC", "EST", "GMT+3", "GMT-3", "UTC+3", "EST5", "EST+5", "EST-5",
    "EST05", "EST005", "EST0500", "EST05:00", "EST5:30", "EST5EDT4",
    "EST5EDT,M3.2.0,M11.1.0", "EST5EDT;M3.2.0;M11.1.0",
    "EST5EDT,M3.2.0/2:30:15,M11.1.0/1:00:00", "EST5EDT,M3.2.0/123,M11.1.0",
    "EST5EDT,M3.0.0,M11.1.0", "EST5EDT,M13.1.0,M11.1.0",
    "EST5EDT,J60,J300", "EST5EDT,59,300", "EST5EDT,400,500",
    "EST5EDT,M3.2.0", "EST5EDT,M3.2.0,M11.1.0,", "EST5EDT,M3-2-0,M11-1-0",
    "EST5EDT,5,4,0,7200,11,3,0,7200,3600",
    "EST5EDT,5,0,15,7200,11,0,10,7200",
    "EST,5,4,0,7200,11,3,0,7200,3600",
    "EST5EDT,5,4,0,7200,11,3,0,7200,+3600",
    "EST5EDT,5,4,0,7200,11,3,0,7200,-3600",
    "BRST+3BRDT", "BRST+3BRDT+2", "BRST+3BRDT+2,M10.3.0,M2.3.0",
    "hdfiughdfuig,dfughdfuigpu87\u00f1::", ",dfughdfuigpu87\u00f1::",
    "-1:WART4WARST,J1,J365/25", "WART4WARST,J1,J365/-25",
    "IST-2IDT,M3.4.-1/26,M10.5.0", "IST-2IDT,M3,2000,1/26,M10,5,0",
    "InvalidString;439999", "A B5", "EST 5", "EST5 EDT", "EST5EDT4,M4.1.0/02:00:00,M10-5-0/02:00",
    "ABC+1:30DEF+0:30", "XYZ12345", "XYZ123", "X1Y2", "X+Y", ":EST5",
    "EST5EDT,M3.2.0/-2,M11.1.0", "EST5EDT,M3.2.0/24,M11.1.0/25",
    "EST5EDT,J0,J365", "EST5EDT,0,365", "EST5EDT,366,0",
]


def parse_record(s):
    from dateutil.parser import _parser
    try:
        res = _parser._parsetz(s)
    except Exception as e:
        parsed = "raise " + type(e).__name__
    else:
        if res is None:
            parsed = "None"
        else:
            parsed = repr(res) + " unused=" + str(res.any_unused_tokens)
    try:
        z = tz.tzstr.instance(s)
    except Exception as e:
        made = "raise " + type(e).__name__
    else:
        parts = []
        for y in (2003, 2030):
            try:
                t = z.transitions(y)
            except Exception as e:
                parts.append("raise")
                continue
            parts.append("None" if t is None else
                         t[0].isoformat() + "," + t[1].isoformat())
        made = "%s %s %s" % (secs(z._std_offset), secs(z._dst_offset),
                             " ".join(parts))
    return "\x1f".join([s, parsed, made])


def mbt_str(s):
    out = []
    for c in s:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif ord(c) < 0x20:
            out.append("\\u{%x}" % ord(c))
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def write_array(f, name, items):
    f.write("///|\nlet %s : Array[String] = [\n" % name)
    for it in items:
        if it is None:
            continue
        f.write("  %s,\n" % mbt_str(it))
    f.write("]\n\n")


def main():
    data = {}
    for zname in SYSTEM_ZONES:
        with open(os.path.join(ZONEINFO, zname), "rb") as fh:
            data[zname] = fh.read()
    for k, v in UPSTREAM.items():
        data[k] = base64.b64decode(v)
    with open(os.path.join(ROOT, "tz", "zone_data_test.mbt"), "w") as f:
        f.write("// Generated by tools/gen_tz_corpus.py -- DO NOT EDIT.\n")
        f.write("// TZif data (system zoneinfo %s plus the base64 constants of\n"
                % open(os.path.join(ZONEINFO, "+VERSION")).read().strip())
        f.write("// upstream tests/test_tz.py), base64 encoded.\n\n")
        f.write("///|\nlet zone_data : Map[String, String] = {\n")
        for k, v in data.items():
            b = base64.b64encode(v).decode()
            f.write("  %s: %s,\n" % (mbt_str(k), mbt_str(b)))
        f.write("}\n")

    with open(os.path.join(ROOT, "tz", "zone_data_wbtest.mbt"), "w") as f:
        f.write("// Generated by tools/gen_tz_corpus.py -- DO NOT EDIT.\n")
        f.write("// Upstream test_tz.py TZif constants for white-box tests.\n\n")
        f.write("///|\nlet wb_zone_data : Map[String, String] = {\n")
        for k, v in UPSTREAM.items():
            b = base64.b64encode(base64.b64decode(v)).decode()
            f.write("  %s: %s,\n" % (mbt_str(k.split(":")[1]), mbt_str(b)))
        f.write("}\n")
    file_recs = []
    for k, v in data.items():
        z = tz.tzfile(io.BytesIO(v), filename=k)
        file_recs.extend(tzfile_records(k, z))
    str_recs = []
    for s in TZSTRS:
        str_recs.extend(tzstr_records("S:" + s, tz.tzstr(s)))
    old_tz = os.environ.get("TZ")
    local_recs = []
    for s in TZLOCAL_STRS:
        local_recs.extend(tzlocal_records(s))
    if old_tz is None:
        del os.environ["TZ"]
    else:
        os.environ["TZ"] = old_tz
    time.tzset()

    with open(os.path.join(ROOT, "tz", "diff_corpus_test.mbt"), "w") as f:
        f.write("// Generated by tools/gen_tz_corpus.py -- DO NOT EDIT.\n")
        f.write("// Records: F|zone|utc|local|fold|utcoffset|dst|tzname\n")
        f.write("//          W|zone|wall|fold|utcoffset|dst|tzname|is_ambiguous|"
                "exists|datetime_ambiguous|as_utc|resolve_imaginary/fold\n\n")
        write_array(f, "tzfile_corpus", file_recs)
        write_array(f, "tzstr_corpus", str_recs)
    path = os.path.join(ROOT, "tz", "diff_corpus_tzlocal_test.mbt")
    with open(path, "w") as f:
        f.write("// Generated by tools/gen_tz_corpus.py -- DO NOT EDIT.\n")
        f.write("// tzlocal() records, keyed L:<TZ value>.\n\n")
        write_array(f, "tzlocal_corpus", local_recs)
    with open(os.path.join(ROOT, "tz", "tzparser_corpus_wbtest.mbt"), "w") as f:
        f.write("// Generated by tools/gen_tz_corpus.py -- DO NOT EDIT.\n")
        f.write("// TZ string \\x1f _parsetz(s) \\x1f tzstr std/dst offsets and\n")
        f.write("// transitions(2003), transitions(2030).\n\n")
        write_array(f, "tzparser_corpus", [parse_record(s) for s in PARSE_STRS])
    print(len(file_recs), len(str_recs), len(local_recs))


if __name__ == "__main__":
    main()
