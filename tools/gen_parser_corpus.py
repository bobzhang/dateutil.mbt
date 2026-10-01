"""Generate parser/corpus_data_test.mbt: a differential corpus of
`parser.parse` (many formats, token soups, fuzzy sentences, zone names and
offsets, dayfirst/yearfirst/fuzzy/ignoretz/tzinfos combinations) and of the
isoparser entry points, with results from the vendored reference.

The reference parserinfo uses a fixed reference year (2026) so two-digit
year expansion is reproducible; the MoonBit side uses
`ParserInfo::new(year=2026)`. Run with a TZ whose names never occur in the
inputs:

  TZ=XXX0 python3 tools/gen_parser_corpus.py > parser/corpus_data_test.mbt
"""
import json
import os
import random
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parser_harness as H  # noqa: E402

rnd = random.Random(20261001)
INFO = H.dparser.parserinfo()
INFO._year = 2026
INFO._century = 2000

DEFAULTS = [datetime(2003, 9, 25), datetime(2010, 1, 31),
            datetime(2024, 2, 29, 13, 14, 15, 161718),
            datetime(1999, 12, 31, 23, 59, 59)]
TZINFOS = {'BRST': -10800, 'EST': -18000, 'CET': 3600, 'UTC': 7200}

parse_cases = []


def run_parse(s, default, **opts):
    kw = dict(opts)
    tokens = kw.pop('tokens', False)
    if tokens:
        kw['fuzzy_with_tokens'] = True
    out, warned, r, _ = H.call_parse(s, INFO, default=default, **kw)
    # Divergence: dateutil's tzoffset accepts offsets of 24h or more (the
    # datetime is then unusable: CPython raises on utcoffset()); the MoonBit
    # tz.tzoffset validates on construction, so parse raises that ValueError.
    # Divergence: decimal.InvalidOperation is reported as ValueError.
    if out.startswith('InvalidOperation: '):
        out = 'ValueError: ' + out[len('InvalidOperation: '):]
    dt_r = r[0] if isinstance(r, tuple) else r
    if dt_r is not None and isinstance(dt_r.tzinfo, H.tz.tzoffset) and \
            abs(dt_r.tzinfo._offset.total_seconds()) >= 86400:
        if abs(dt_r.tzinfo._offset.total_seconds()) > 2 ** 31 - 1:
            out = 'OverflowError: Python int too large to convert to C int'
        else:
            out = ('ValueError: offset must be a timedelta strictly between '
                   '-timedelta(hours=24) and timedelta(hours=24).')
    o = {'default': [default.year, default.month, default.day, default.hour,
                     default.minute, default.second, default.microsecond]}
    for k, v in opts.items():
        if k == 'tzinfos':
            o[k] = [[n, x] for n, x in v.items()]
        else:
            o[k] = v
    parse_cases.append([s, o, out, warned])


OPTION_POOL = [
    {}, {'dayfirst': True}, {'yearfirst': True},
    {'dayfirst': True, 'yearfirst': True}, {'dayfirst': False, 'yearfirst': False},
    {'fuzzy': True}, {'tokens': True}, {'ignoretz': True},
    {'tzinfos': TZINFOS}, {'fuzzy': True, 'tzinfos': TZINFOS},
    {'tokens': True, 'dayfirst': True},
]


def add(s, n_opts=2):
    run_parse(s, DEFAULTS[0])
    for _ in range(n_opts):
        run_parse(s, rnd.choice(DEFAULTS), **rnd.choice(OPTION_POOL))


def rand_dt():
    y = rnd.choice([rnd.randint(1900, 2099), rnd.randint(1970, 2030)])
    d = datetime(y, 1, 1) + timedelta(days=rnd.randint(0, 364),
                                       seconds=rnd.randint(0, 86399),
                                       microseconds=rnd.choice([0, 0, rnd.randint(0, 999999)]))
    return d


FORMATS = [
    '%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M:%S.%f', '%Y%m%dT%H%M%S',
    '%Y%m%d', '%y%m%d', '%d/%m/%Y', '%m/%d/%Y', '%d/%m/%y', '%m/%d/%y',
    '%d.%m.%Y', '%d.%m.%y %H:%M', '%Y.%m.%d', '%d-%b-%Y', '%b %d %Y',
    '%B %d, %Y', '%d %B %Y', '%a %b %d %H:%M:%S %Y', '%A, %B %d, %Y %I:%M %p',
    '%a, %d %b %Y %H:%M:%S', '%H:%M', '%H:%M:%S', '%I:%M%p', '%I %p',
    '%I:%M:%S %p', '%b %Y', '%B', '%A', '%a', '%Y', '%d %b', '%b-%d-%y',
    '%Y/%b/%d', '%d%b%Y', '%H%M%S', '%Hh%Mm%Ss', '%Hh%M', '%Mm%Ss',
    '%Y-%m-%dT%H:%M', '%Y-%m-%dT%H', '%j', '%y', '%d', '%m-%Y', '%Y %d %m',
    '%c', '%x', '%X',
]

TZ_SUFFIXES = ['', '', ' UTC', ' GMT', 'Z', 'z', ' BRST', ' EST', ' PDT', ' CET',
               ' +0300', ' -0300', '+03:00', '-05:00', ' +3', ' -11', ' GMT+3',
               ' UTC-5', ' BRST+3', ' -0300 (BRST)', ' +0000', '-00:00', ' z',
               ' +01:30', ' +2500', ' JST', ' XYZW', ' A']

for _ in range(450):
    d = rand_dt()
    fmt = rnd.choice(FORMATS)
    s = d.strftime(fmt)
    if rnd.random() < 0.35 and '%H' in fmt or '%I' in fmt and rnd.random() < 0.3:
        s += rnd.choice(TZ_SUFFIXES)
    add(s)

# Token soups
MONTHS = ['Jan', 'January', 'feb', 'Sept', 'SEP', 'September', 'Dec', 'May',
          'october', 'Mar.']
WEEKDAYS = ['Mon', 'Tuesday', 'wed', 'THU', 'Fri', 'Sun', 'Sat']
JUMPS = [' ', ' ', ' ', '.', ',', ';', '-', '/', "'", 'at', 'on', 'and', 'ad',
         'of', 'st', 'nd', 'rd', 'th', 'T', 'm', 't', ' of ', ', ']
AMPM = ['am', 'pm', 'AM', 'PM', 'a', 'p', 'a.m.', 'P.M.', 'A.M']
HMS = ['h', 'm', 's', 'hours', 'minute', 'seconds', 'H', 'M', 'S']
TZN = ['UTC', 'GMT', 'Z', 'z', 'BRST', 'EST', 'PST', 'CET', 'ABCDE', 'ABCDEF', 'X']
WORDS = ['Today', 'is', 'meeting', 'the', 'I', 'have', 'a', 'see', 'you',
         'http://x.com/p/600221.html', 'foo', 'bar', 'exactly', 'with', 'timezone',
         '(', ')', '[', ']', '!', '?', ':', '+', '-', '@', '#', '%']


def num():
    k = rnd.random()
    if k < 0.3:
        return str(rnd.randint(0, 31))
    if k < 0.45:
        return '%02d' % rnd.randint(0, 99)
    if k < 0.6:
        return str(rnd.randint(1900, 2100))
    if k < 0.7:
        return str(rnd.randint(0, 10 ** rnd.randint(1, 15)))
    if k < 0.8:
        return '%d.%d' % (rnd.randint(0, 99), rnd.randint(0, 999999))
    if k < 0.85:
        return '%d,%d' % (rnd.randint(0, 99), rnd.randint(0, 999))
    if k < 0.92:
        return '%02d:%02d' % (rnd.randint(0, 30), rnd.randint(0, 70))
    return '%02d:%02d:%02d.%d' % (rnd.randint(0, 25), rnd.randint(0, 60),
                                  rnd.randint(0, 61), rnd.randint(0, 9999999))


def piece():
    k = rnd.random()
    if k < 0.35:
        return num()
    if k < 0.45:
        return rnd.choice(MONTHS)
    if k < 0.5:
        return rnd.choice(WEEKDAYS)
    if k < 0.65:
        return rnd.choice(JUMPS)
    if k < 0.7:
        return rnd.choice(AMPM)
    if k < 0.75:
        return rnd.choice(HMS)
    if k < 0.82:
        return rnd.choice(TZN)
    if k < 0.87:
        return rnd.choice(['+', '-']) + rnd.choice(['0300', '03:00', '3', '12', '930', '0530'])
    return rnd.choice(WORDS)


for _ in range(600):
    n = rnd.randint(1, 8)
    parts = [piece() for _ in range(n)]
    sep_style = rnd.random()
    if sep_style < 0.5:
        s = ' '.join(parts)
    elif sep_style < 0.8:
        s = ''.join(parts)
    else:
        s = rnd.choice(['-', '/', '.', ', ']).join(parts)
    add(s)

# Fuzzy sentences
TEMPLATES = [
    'Today is {d}, exactly at {t} with timezone {z}.',
    'I have a meeting on {d} at {t}',
    'Meet me at the AM/PM on Sunset at {t} on {d}',
    '{d} was a good day',
    'On {d}, I am going to be the first man on Mars',
    'Your order {n} shipped {d} {t}',
    'Price: 14.99 (25% off, until {d})',
    'Jan 29, 1945 14:45 AM I going to see you there?',
    'Event: {t} {z} on the {o} of {m}, {y}',
    '{n} MARTIN TRUST u/a/d {d}',
]
for _ in range(200):
    d = rand_dt()
    s = rnd.choice(TEMPLATES).format(
        d=d.strftime(rnd.choice(['%B %d, %Y', '%d %b %Y', '%Y-%m-%d', '%m/%d/%y', '%d.%m.%Y', '%b %d'])),
        t=d.strftime(rnd.choice(['%H:%M', '%I:%M %p', '%H:%M:%S', '%I%p', '%Hh%M'])),
        z=rnd.choice(['-03:00', '+0100', 'UTC', 'BRST', 'EST', 'Z', '']),
        n=str(rnd.randint(1, 99999)),
        o=rnd.choice(['1st', '2nd', '3rd', '4th', '21st', '30th']),
        m=d.strftime('%B'), y=str(d.year))
    run_parse(s, DEFAULTS[0], fuzzy=True)
    run_parse(s, rnd.choice(DEFAULTS), tokens=True)
    run_parse(s, rnd.choice(DEFAULTS), fuzzy=True, tzinfos=TZINFOS,
              dayfirst=rnd.choice([True, False]))

# Edge cases
EDGES = [
    '', ' ', ',', '\x00', '\x00\x00August 29, 1924', 'nan', 'NaN 2003', 'inf',
    'Infinity', '1e5', '1.e', '12.', '.5', '5.', '1_000', '99999999999',
    '9999999999999999999999', '2003 99999999999', '10:99999999999', 'Sep 3000000000',
    '99999 Sep 3', '10:00 +9999', '10:00 +2500', '9999-12-31 Mon',
    '٢٠٠٣-٠٩-٢٥', '\U0001d7d0\U0001d7ce\U0001d7ce\U0001d7d1-09-25',
    '2003-09-25 10:00 ２０', 'Sept² 2003', '²³', '25 Сентябрь 2003',
    '10　09　2003', '2003–2–1', '0000 Jun 20', 'Feb 30, 2007', '0-100',
    '2014-15-25', '2014-02-28 22:64', '2014-02-28 25:16 PM', '2014-02-28 22:14:64',
    '1237 PM BRST Mon Oct 30 2017', '1991041310:19:24', '0031 Nov 03', 'A.D.2001',
    ' 6AD May 19', 'Frid Dec 30, 2016', '1,700', '2:15 PM on January 2nd 1973 A.D.',
    '201712', '00:00 PM', '12:00 AM', '12 am', '0 pm', '13 pm', '12h am', '5.5h',
    '5.5m 3s', '10 h 36.5', '1h 2h', '3 s', 'm 5', '5 m', '12h04m', '12 h', 'h 12',
    'Jan of 01', 'Jan of 2001', 'Jan of x', 'Jan-01-99', 'Jan/01', 'Jan-Feb', '01-Jan-99',
    '01-99-Jan', '99-01-Jan', '2003-Sep-25', '25 Sep 03', 'Sep 25 03', '03 Sep 25',
    '1 2 3', '1 2', '32 1', '1 32', '13 1', '1 13 99', '99 13 1', '12 13 14',
    'GMT+3', '10:00 GMT+3', '10:00 GMT-3', '10:00 BRST+3', '10:00 UTC+3:30',
    '10:00 -03:00 (BRST)', '10:00 -0300 (BR)', '10:00 - 0300', '10:00 +', '10:00 -12345',
    '10:00 Z', '10:00 z', '10:00 UTC', '10:00 GMT', '10:00 ABCDEF', '10:00 EsT',
    'Thu Sep 25 10:36:28 BRST 2003', '2003 10:36:28 BRST 25 Sep Thu', '4.2h', '4.2.2003',
    '4.Sep.2003', 'Sep.4.2003', 'a.m.', '10 a.m. 3', 'Mon 10', 'Monday Monday',
    '1999 2000', '1999 Jan 2000', 'Jan Feb', '19990101T23', '19990101T2359', '1999010123',
    '990101 2359', '990101 235959.5', '235959.5', '2359595', '1234.5678', '123456.7',
    '12345678.5', '20030925T104941.5-0300', '2003-09-25T10:49:41.5-03:00',
    '2003-09-25T10:49:41,5', '10:49:41,502', '10,5', '1,5', '2003-09-25 24:00',
    'December.0031.30', '13NOV2017', '02:17NOV2017', 'AD2001', 'Sa 21. Jan 2017',
    '0:00 PM, PST', '5:50 A.M. on June 13, 1990', 'April 2009', 'Feb 2007', 'Feb 2008',
    '2004 10 Apr 11h30m', '01m02h', '01h02s', '36 m 05 s', '10h pm', '10:00a.m', 'Wed',
    'Sep 03', 'Sep of 03', 'Sep of 2003 03', 'of Sep', '3rd of May 2001', '31-Dec-00',
    '0099-01-01T00:00:00', '0003-03-04', 'İstanbul 2003',
    # review findings: saturation, decimal context, digit limit, big offsets
    '92233720368547760080', 'Jan-92233720368547760080', '922337203685477580',
    '0.99999999999999999999999999999h', '0.99999999999999999999999999999m',
    '10:0.99999999999999999999999999999', '12345678901234567890123456789h',
    '1234567890123456789012345678h', 'Jan-' + '1' * 4301, '1' * 4301,
    '10:00 +999999:00', '10:00 -99:99', 'ΑΣ Jan 2003', '中Σ 2003',
]
for s in EDGES:
    add(s, n_opts=3)

# --- isoparser -----------------------------------------------------------
iso_cases = []


def run_iso(method, s, sep=None, **kw):
    out, _, _ = H.call_iso(sep, method, s, **kw)
    o = {}
    if sep is not None:
        o['sep'] = sep
    o.update(kw)
    iso_cases.append([method, s, o, out])


ISO_DATE_FMTS = ['%Y', '%Y-%m', '%Y-%m-%d', '%Y%m%d', '%G-W%V', '%GW%V',
                 '%G-W%V-%u', '%GW%V%u', '%Y-%j', '%Y%j']
ISO_TIME_FMTS = ['%H', '%H:%M', '%H%M', '%H:%M:%S', '%H%M%S', '%H:%M:%S.%f',
                 '%H%M%S.%f', '%H:%M:%S,%f']
ISO_TZ = ['', '', 'Z', 'z', '+00:00', '-00:00', '+0000', '+00', '-05', '+05:30',
          '-0330', '+23:59', '-23', '+24:00', '+00:60', '+1', '+123', '+12:345',
          '05:00', '_05:00', '+05:3', '+-1', '+ 1', '+05-30']
MUTATIONS = [
    lambda s: s[:-1], lambda s: s + '0', lambda s: s.replace('-', '', 1),
    lambda s: s.replace(':', '', 1), lambda s: s.replace('T', ' '),
    lambda s: s.replace('T', 'X'), lambda s: s.replace('0', ' ', 1),
    lambda s: s.replace('1', '_', 1), lambda s: s.replace('.', ',', 1),
    lambda s: s + 'Z', lambda s: s + '+', lambda s: s.replace('2', '+', 1),
    lambda s: s[1:], lambda s: s.upper(), lambda s: s.lower(),
]
for _ in range(600):
    d = rand_dt()
    dpart = d.strftime(rnd.choice(ISO_DATE_FMTS))
    if rnd.random() < 0.7 and len(dpart) >= 7:
        tfmt = rnd.choice(ISO_TIME_FMTS)
        tpart = d.strftime(tfmt)
        if '%f' in tfmt:
            tpart = tpart[:len(tpart) - rnd.randint(0, 5)]
            if rnd.random() < 0.2:
                tpart += '123456789'[:rnd.randint(1, 9)]
        if rnd.random() < 0.05:
            tpart = '24' + tpart[2:].replace('1', '0').replace('2', '0')
        s = dpart + rnd.choice(['T', 'T', ' ', 'x', '_']) + tpart + rnd.choice(ISO_TZ)
    else:
        s = dpart
    if rnd.random() < 0.3:
        s = rnd.choice(MUTATIONS)(s)
    run_iso('isoparse', s)
    if rnd.random() < 0.2:
        run_iso('isoparse', s, sep=rnd.choice(['T', ' ', 'x']))
    run_iso('parse_isodate', dpart if rnd.random() < 0.7 else s)
for _ in range(200):
    d = rand_dt()
    t = d.strftime(rnd.choice(ISO_TIME_FMTS)) + rnd.choice(ISO_TZ)
    if rnd.random() < 0.3:
        t = rnd.choice(MUTATIONS)(t)
    run_iso('parse_isotime', t)
for z in ISO_TZ + ['Z', 'z', 'UTC', '+5', '+05:00:00', '', '+0', '+05 ']:
    run_iso('parse_tzstr', z)
    run_iso('parse_tzstr', z, zero_as_utc=False)
for s in ['2014-W00', '2014-W54', '2009-W53-7', '0001-W01-1', '9999-W52-7',
          '9999-12-31T24:00', '0001-001', '2016-366', '2017-366', '20170', '2017-0',
          '2017-W1', '2017-W011', '2017W01-1', '-001-01-01', '+201-01-01', ' 201-01-01',
          '2014-01-01T1:2:3', '2014-01-01T01:02:03.', '2014-01-01T01:02:03.1234567Z',
          '2014-01-01T01:02:03.123+05', '2014-01-01T01:02:03.123+05:00:00',
          '2014-01-01Tab', '2014-01-01T', '2014-01-01T1', '٢٠١٤',
          '2014–01–01', '2014-01-01T12:30:00−', '2014-02-30', '2014-13-01']:
    run_iso('isoparse', s)
    run_iso('parse_isodate', s)
for sep in ['T', ' ', 'x', '1', '', 'TT', 'é', '\U0001f35b', '-', ':']:
    run_iso('isoparse', '2014-01-01' + (sep or 'T') + '12:00', sep=sep)


print('// Generated by tools/gen_parser_corpus.py from the vendored reference; do not edit.')
print('// %d parse cases, %d isoparser cases.' % (len(parse_cases), len(iso_cases)))
print()
print('///|')
print('/// JSON lines: [timestr, options, expected, warned tznames].')
print('let parse_corpus : String =')
for c in parse_cases:
    print('  #|' + json.dumps(c, ensure_ascii=True, separators=(',', ':')))
print()
print('///|')
print('/// JSON lines: [method, input, options, expected].')
print('let iso_corpus : String =')
for c in iso_cases:
    print('  #|' + json.dumps(c, ensure_ascii=True, separators=(',', ':')))
