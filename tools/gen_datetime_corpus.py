"""Generate datetime/cpython_corpus_test.mbt from CPython's datetime module.

Run: python3 tools/gen_datetime_corpus.py > datetime/cpython_corpus_test.mbt
"""
import random
from datetime import datetime, date, time, timedelta, timezone

rnd = random.Random(20261001)
out = []


def mbt_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t') + '"'


def fl(v):
    r = repr(float(v))
    if 'e' in r:
        m, e = r.split('e')
        if '.' not in m:
            m += '.0'
        r = m + 'e' + e
    return r


def emit(name, lines):
    out.append('///|\ntest "%s" {\n%s\n}\n' % (name, '\n'.join('  ' + l for l in lines)))


def rdate():
    o = rnd.randint(1, date.max.toordinal())
    if rnd.random() < 0.3:
        o = rnd.randint(date(1899, 1, 1).toordinal(), date(2101, 1, 1).toordinal())
    return date.fromordinal(o)


# ordinals, weekday, isocalendar
lines = []
for _ in range(300):
    d = rdate()
    lines.append('check_date(%d, %d, %d, ordinal=%d, weekday=%d, iso=(%d, %d, %d), yday=%d)' % (
        d.year, d.month, d.day, d.toordinal(), d.weekday(), *d.isocalendar(), d.timetuple().tm_yday))
for y in [1, 4, 100, 400, 1900, 2000, 2004, 9999]:
    for (m, dd) in [(1, 1), (2, 28), (3, 1), (12, 31)]:
        d = date(y, m, dd)
        lines.append('check_date(%d, %d, %d, ordinal=%d, weekday=%d, iso=(%d, %d, %d), yday=%d)' % (
            d.year, d.month, d.day, d.toordinal(), d.weekday(), *d.isocalendar(), d.timetuple().tm_yday))
emit("cpython: ordinals, weekdays, iso calendar", lines)

# timedelta int constructor, str, repr
lines = []
for _ in range(200):
    args = dict(days=rnd.randint(-10**6, 10**6), seconds=rnd.randint(-10**7, 10**7),
                microseconds=rnd.randint(-10**8, 10**8), milliseconds=rnd.randint(-10**5, 10**5),
                minutes=rnd.randint(-10**5, 10**5), hours=rnd.randint(-10**4, 10**4), weeks=rnd.randint(-1000, 1000))
    keys = [k for k in args if rnd.random() < 0.5] or ['seconds']
    a = {k: args[k] for k in keys}
    td = timedelta(**a)
    call = ', '.join('%s=%d' % (k, v) for k, v in a.items())
    lines.append('check_td(@datetime.TimeDelta::new(%s), %s, %s, %s)' % (call, mbt_str(str(td)), mbt_str(repr(td)), fl(td.total_seconds())))
emit("cpython: timedelta int constructor", lines)

lines = []
for _ in range(1500):
    args = dict(days=rnd.uniform(-1000, 1000), seconds=rnd.uniform(-10**6, 10**6),
                microseconds=rnd.uniform(-10**7, 10**7), milliseconds=rnd.uniform(-10**4, 10**4),
                minutes=rnd.uniform(-10**4, 10**4), hours=rnd.uniform(-100, 100), weeks=rnd.uniform(-10, 10))
    keys = [k for k in args if rnd.random() < 0.4] or ['days']
    a = {k: round(args[k], rnd.choice([1, 2, 3, 6])) for k in keys}
    td = timedelta(**a)
    call = ', '.join('%s=%s' % (k, fl(v)) for k, v in a.items())
    lines.append('check_td(@datetime.TimeDelta::from_float(%s), %s, %s, %s)' % (call, mbt_str(str(td)), mbt_str(repr(td)), fl(td.total_seconds())))
for v in [0.5, 1.5, 2.5, -0.5, -1.5, 0.0000005, 0.0000015, 0.0000025, -0.0000025]:
    td = timedelta(seconds=v)
    lines.append('check_td(@datetime.TimeDelta::from_float(seconds=%s), %s, %s, %s)' % (fl(v), mbt_str(str(td)), mbt_str(repr(td)), fl(td.total_seconds())))
emit("cpython: timedelta float constructor", lines)

# datetime + timedelta, datetime - datetime
lines = []
for _ in range(300):
    d = datetime.combine(rdate(), time(rnd.randint(0, 23), rnd.randint(0, 59), rnd.randint(0, 59), rnd.choice([0, rnd.randint(0, 999999)])))
    td = timedelta(days=rnd.randint(-5000, 5000), seconds=rnd.randint(-200000, 200000), microseconds=rnd.randint(-2000000, 2000000))
    try:
        r = d + td
        res = 'Some(%s)' % mbt_str(str(r))
    except OverflowError:
        res = 'None'
    lines.append('check_add(%s, @datetime.TimeDelta::new(days=%d, seconds=%d, microseconds=%d), %s)' % (
        '@datetime.DateTime::new(%d, %d, %d, hour=%d, minute=%d, second=%d, microsecond=%d)' % (
            d.year, d.month, d.day, d.hour, d.minute, d.second, d.microsecond),
        td.days, td.seconds, td.microseconds, res))
emit("cpython: datetime + timedelta", lines)

lines = []
for _ in range(200):
    a = datetime.combine(rdate(), time(rnd.randint(0, 23), rnd.randint(0, 59), rnd.randint(0, 59), rnd.randint(0, 999999)))
    b = datetime.combine(rdate(), time(rnd.randint(0, 23), rnd.randint(0, 59), rnd.randint(0, 59), rnd.randint(0, 999999)))
    ta = timezone(timedelta(minutes=rnd.randint(-23*60, 23*60)))
    tb = timezone(timedelta(minutes=rnd.randint(-23*60, 23*60)))
    a = a.replace(tzinfo=ta); b = b.replace(tzinfo=tb)
    diff = a - b
    c = (a > b) - (a < b)
    lines.append('check_diff(%s, %s, %s, %d)' % (
        '@datetime.DateTime::new(%d, %d, %d, hour=%d, minute=%d, second=%d, microsecond=%d, tzinfo=@datetime.Tz::fixed(@datetime.TimeDelta::new(minutes=%d)))' % (
            a.year, a.month, a.day, a.hour, a.minute, a.second, a.microsecond, ta.utcoffset(None) // timedelta(minutes=1)),
        '@datetime.DateTime::new(%d, %d, %d, hour=%d, minute=%d, second=%d, microsecond=%d, tzinfo=@datetime.Tz::fixed(@datetime.TimeDelta::new(minutes=%d)))' % (
            b.year, b.month, b.day, b.hour, b.minute, b.second, b.microsecond, tb.utcoffset(None) // timedelta(minutes=1)),
        mbt_str(repr(diff)), c))
emit("cpython: aware datetime difference and ordering", lines)

# strftime / isoformat / repr / str
fmts = ['%a %A %b %B %d %H %I %j %m %M %p %S %U %w %W %y %Y %f %%', '%c', '%x %X', '%G-W%V-%u',
        '%-d/%-m/%y %-H:%-M:%-S', '%e|%D|%F|%T|%R|%C|%h']
lines = []
for _ in range(120):
    d = datetime.combine(rdate(), time(rnd.randint(0, 23), rnd.randint(0, 59), rnd.randint(0, 59), rnd.choice([0, rnd.randint(0, 999999)])))
    if d.year < 1000:
        d = d.replace(year=d.year + 1000)
    f = rnd.choice(fmts)
    ctor = '@datetime.DateTime::new(%d, %d, %d, hour=%d, minute=%d, second=%d, microsecond=%d)' % (
        d.year, d.month, d.day, d.hour, d.minute, d.second, d.microsecond)
    lines.append('check_fmt(%s, %s, %s, %s, %s, %s)' % (ctor, mbt_str(f), mbt_str(d.strftime(f)),
                 mbt_str(str(d)), mbt_str(repr(d)), mbt_str(d.isoformat())))
emit("cpython: formatting", lines)

# utcfromtimestamp
lines = []
for _ in range(100):
    t = rnd.choice([rnd.randint(-10**10, 10**10), round(rnd.uniform(-10**9, 10**10), 6)])
    d = datetime.fromtimestamp(t, timezone.utc).replace(tzinfo=None)
    lines.append('check_ts(%s, %s)' % (fl(t), mbt_str(str(d))))
emit("cpython: utcfromtimestamp", lines)

print('// Generated by tools/gen_datetime_corpus.py from CPython; do not edit.\n')
print('\n'.join(out))
