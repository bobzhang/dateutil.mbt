"""Shared helpers for the parser test generators: load the vendored
dateutil, record calls to its parser API and translate them into MoonBit
check calls (see parser/helpers_test.mbt)."""
import os
import sys
import warnings
from datetime import datetime, date, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for p in (os.path.join(ROOT, '.repos/dateutil'),
          os.path.join(ROOT, '.repos/dateutil/src'),
          os.path.join(ROOT, 'tools/pyshim')):
    if p not in sys.path:
        sys.path.insert(0, p)

from dateutil import parser as dparser  # noqa: E402
from dateutil import tz  # noqa: E402
from dateutil.parser import UnknownTimezoneWarning  # noqa: E402
from dateutil.parser import _parser as _dparser_impl  # noqa: E402

# Freeze "now" so that generated expectations do not depend on the day the
# generator runs: `parse()` without `default` uses today's date and
# `parserinfo` uses the current year to expand two-digit years. The MoonBit
# side (parser/helpers_test.mbt `check_parse`) pins the same values.
FROZEN_NOW = datetime(2026, 10, 1, 12, 0, 0)


class _FrozenDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        if tz is None:
            return FROZEN_NOW
        return tz.fromutc(FROZEN_NOW.replace(tzinfo=tz))


class _FrozenDatetimeModule(object):
    def __getattr__(self, name):
        import datetime as _real
        return getattr(_real, name)


_frozen_dt_module = _FrozenDatetimeModule()
_frozen_dt_module.datetime = _FrozenDatetime


class _FrozenTimeModule(object):
    def __getattr__(self, name):
        import time as _real
        return getattr(_real, name)

    def localtime(self, *args):
        import time as _real
        if args:
            return _real.localtime(*args)
        return FROZEN_NOW.timetuple()


_dparser_impl.datetime = _frozen_dt_module
_dparser_impl.time = _FrozenTimeModule()

REAL_parse = dparser.parse
REAL_isoparser = dparser.isoparser


class Untranslatable(Exception):
    pass


def mbt_str(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append('\\t')
        elif ch == '\r':
            out.append('\\r')
        elif o < 0x20 or 0x7f <= o < 0xa0 or (0xd800 <= o < 0xe000) \
                or ch.isspace() and ch != ' ':
            out.append('\\u{%x}' % o)
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


def mbt_bool(b):
    return 'true' if b else 'false'


def mbt_dt(d):
    if not isinstance(d, datetime) or d.tzinfo is not None or d.fold:
        raise Untranslatable('default %r' % (d,))
    args = [str(d.year), str(d.month), str(d.day)]
    for name in ('hour', 'minute', 'second', 'microsecond'):
        v = getattr(d, name)
        if v:
            args.append('%s=%d' % (name, v))
    return 'dt(%s)' % ', '.join(args)


def fmt_exc(e):
    return '%s: %s' % (type(e).__name__, e)


def fmt_value(v):
    if isinstance(v, tuple):
        return '(%s, %s)' % (repr(v[0]), repr(tuple(v[1])))
    return repr(v)


def call_parse(timestr, parserinfo=None, **kwargs):
    """Run the reference parse; return (result string, warned tznames)."""
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter('always')
        try:
            r = REAL_parse(timestr, parserinfo, **kwargs)
            out = fmt_value(r)
            exc = None
        except Exception as e:  # noqa: BLE001
            out = fmt_exc(e)
            exc = e
            r = None
    warned = []
    for x in w:
        if issubclass(x.category, UnknownTimezoneWarning):
            msg = str(x.message)
            warned.append(msg.split(' ')[1])
    return out, warned, r, exc


def translate_parse(timestr, parserinfo, kwargs, out, warned):
    if not isinstance(timestr, str):
        raise Untranslatable('timestr %r' % (timestr,))
    if parserinfo is not None:
        raise Untranslatable('parserinfo')
    args = [mbt_str(timestr), mbt_str(out)]
    for k, v in kwargs.items():
        if k == 'default':
            if v is not None:
                args.append('default=' + mbt_dt(v))
        elif k in ('ignoretz', 'dayfirst', 'yearfirst', 'fuzzy'):
            if v is None:
                continue
            if not isinstance(v, bool):
                raise Untranslatable('%s=%r' % (k, v))
            args.append('%s=%s' % (k, mbt_bool(v)))
        elif k == 'fuzzy_with_tokens':
            if v:
                args.append('tokens=true')
        elif k == 'tzinfos':
            if not isinstance(v, dict) or not all(
                    isinstance(x, int) and isinstance(n, str)
                    for n, x in v.items()):
                raise Untranslatable('tzinfos %r' % (v,))
            args.append('tzinfos=offsets([%s])' % ', '.join(
                '(%s, %d)' % (mbt_str(n), x) for n, x in v.items()))
        else:
            raise Untranslatable('kwarg %s' % k)
    if warned:
        args.append('warns=[%s]' % ', '.join(mbt_str(x) for x in warned))
    return 'check_parse(%s)' % ', '.join(args)


def iso_input(s):
    if isinstance(s, bytes):
        try:
            return s.decode('ascii')
        except UnicodeDecodeError:
            raise Untranslatable('non-ascii bytes')
    if not isinstance(s, str):
        raise Untranslatable('iso input %r' % (s,))
    return s


def call_iso(sep, method, s, **kw):
    try:
        p = REAL_isoparser(sep=sep) if sep is not None else REAL_isoparser()
        r = getattr(p, method)(s, **kw)
        return repr(r), r, None
    except Exception as e:  # noqa: BLE001
        return fmt_exc(e), None, e


def translate_iso(sep, method, s, kw, out):
    fn = {'isoparse': 'check_isoparse', 'parse_isodate': 'check_isodate',
          'parse_isotime': 'check_isotime', 'parse_tzstr': 'check_tzstr'}[method]
    args = [mbt_str(iso_input(s)), mbt_str(out)]
    if sep is not None:
        if not isinstance(sep, str):
            raise Untranslatable('sep %r' % (sep,))
        args.append('sep=' + mbt_str(sep))
    for k, v in kw.items():
        if k == 'zero_as_utc':
            args.append('zero_as_utc=' + mbt_bool(v))
        else:
            raise Untranslatable('kwarg %s' % k)
    return '%s(%s)' % (fn, ', '.join(args))


def emit_test(out, name, lines):
    out.append('///|\ntest %s {\n%s\n}\n' % (
        mbt_str(name), '\n'.join('  ' + l for l in lines)))
