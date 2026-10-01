"""Generate parser/upstream_generated_test.mbt by running dateutil's own
tests/test_parser.py and tests/test_isoparser.py (every parametrization,
including xfail tests) against the vendored reference, recording each call
to `parse` / `isoparse` / `isoparser` together with the reference result.

Tests whose calls cannot be expressed through the generated helpers (custom
parserinfo subclasses, zone objects in `tzinfos`, bytes/stream inputs, ...)
are listed on stderr; they are ported by hand in parser/*_test.mbt.

Run: TZ=XXX0 python3 tools/gen_parser_upstream_tests.py > parser/upstream_generated_test.mbt
"""
import contextlib
import inspect
import itertools
import os
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parser_harness as H  # noqa: E402


# --- a pytest stand-in that records parametrize arguments -----------------
class _Mark:
    def __getattr__(self, name):
        def deco(*args, **kwargs):
            if name == 'parametrize':
                argnames, argvalues = args[0], list(args[1])

                def wrap(f):
                    f._params = getattr(f, '_params', []) + [(argnames, argvalues)]
                    return f
                return wrap
            if len(args) == 1 and callable(args[0]) and not kwargs:
                f = args[0]
                if name == 'xfail':
                    f._xfail = True
                return f

            def wrap(f):
                if name == 'xfail' and (not args or args[0]):
                    f._xfail = True
                if name == 'skipif' and args and args[0]:
                    f._skip = kwargs.get('reason', 'skipif')
                return f
            return wrap
        return deco


class _Fail(Exception):
    pass


pytest = types.ModuleType('pytest')
pytest.mark = _Mark()


def _fixture(*args, **kwargs):
    if len(args) == 1 and callable(args[0]) and not kwargs:
        return args[0]
    return lambda f: f


class _ExcInfo(object):
    value = None


@contextlib.contextmanager
def _raises(exc, *args, **kwargs):
    info = _ExcInfo()
    try:
        yield info
    except exc as e:
        info.value = e
        return
    raise AssertionError('did not raise')


@contextlib.contextmanager
def _warns(cat, *args, **kwargs):
    yield


def _pfail(msg=''):
    raise _Fail(msg)


pytest.fixture = _fixture
pytest.raises = _raises
pytest.warns = _warns
pytest.fail = _pfail
pytest.param = lambda *a, **k: a
sys.modules['pytest'] = pytest

import tests.test_parser as tp  # noqa: E402
import tests.test_isoparser as ti  # noqa: E402

FIXTURES = {'fuzzy': [True, False]}
# Depend on the process TZ environment (TZEnvContext); ported by hand.
SKIP_CLASSES = {'TestTZVar': 'sets the TZ environment variable'}

# --- recording wrappers ---------------------------------------------------
STATE = {'lines': None, 'bad': None}


def note(fn):
    try:
        STATE['lines'].append(fn())
    except H.Untranslatable as e:
        STATE['bad'] = STATE['bad'] or str(e)


def rec_parse(timestr, parserinfo=None, **kwargs):
    out, warned, r, exc = H.call_parse(timestr, parserinfo, **kwargs)
    note(lambda: H.translate_parse(timestr, parserinfo, kwargs, out, warned))
    if exc is not None:
        raise exc
    return r


class RecParser(object):
    def __init__(self, info=None):
        self.info = info

    def parse(self, timestr, **kwargs):
        return rec_parse(timestr, self.info, **kwargs)


class RecIsoparser(object):
    def __init__(self, sep=None):
        self.sep = sep
        try:
            H.REAL_isoparser(sep=sep)
            out, exc = 'ok', None
        except Exception as e:  # noqa: BLE001
            out, exc = H.fmt_exc(e), e

        def tr():
            if not isinstance(sep, str):
                raise H.Untranslatable('sep %r' % (sep,))
            return 'check_isoparser_new(%s, %s)' % (H.mbt_str(sep), H.mbt_str(out))
        if exc is not None or sep is not None:
            note(tr)
        if exc is not None:
            raise exc

    def _call(self, method, s, **kw):
        out, r, exc = H.call_iso(self.sep, method, s, **kw)
        note(lambda: H.translate_iso(self.sep, method, s, kw, out))
        if exc is not None:
            raise exc
        return r

    def isoparse(self, s):
        return self._call('isoparse', s)

    def parse_isodate(self, s):
        return self._call('parse_isodate', s)

    def parse_isotime(self, s):
        return self._call('parse_isotime', s)

    def parse_tzstr(self, s, zero_as_utc=True):
        return self._call('parse_tzstr', s, zero_as_utc=zero_as_utc)


def rec_isoparse(s):
    return RecIsoparser().isoparse(s)


tp.parse = rec_parse
ti.isoparse = rec_isoparse
ti.isoparser = RecIsoparser
H.dparser.parser = RecParser  # `from dateutil.parser import parser` inside tests


# --- running the tests ----------------------------------------------------
def combos(f):
    names_seen = set()
    out = [{}]
    for argnames, values in getattr(f, '_params', []):
        names = ([n.strip() for n in argnames.split(',')]
                 if isinstance(argnames, str) else list(argnames))
        names_seen.update(names)
        new = []
        for c in out:
            for v in values:
                vals = v if len(names) > 1 else (v,)
                d = dict(c)
                d.update(zip(names, vals))
                new.append(d)
        out = new
    sig = inspect.signature(f)
    for name, values in FIXTURES.items():
        if name in sig.parameters and name not in names_seen:
            out = [dict(c, **{name: v}) for c in out for v in values]
    return out


def collect(module, prefix):
    items = []
    for name, obj in vars(module).items():
        if name.startswith('test') and inspect.isfunction(obj):
            items.append(('%s::%s' % (prefix, name), None, name, obj))
        elif inspect.isclass(obj) and (name.startswith('Test') or name.endswith('Test')):
            for mname, m in vars(obj).items():
                if mname.startswith('test') and inspect.isfunction(m):
                    items.append(('%s::%s::%s' % (prefix, name, mname), obj, mname, m))
    return items


def run(module, prefix, out):
    for title, cls, mname, f in collect(module, prefix):
        if cls is not None and cls.__name__ in SKIP_CLASSES:
            sys.stderr.write('SKIP %s (%s)\n' % (title, SKIP_CLASSES[cls.__name__]))
            continue
        if getattr(f, '_skip', None) or (cls is not None and getattr(cls, '_skip', None)):
            sys.stderr.write('SKIP %s (%s)\n' % (title, getattr(f, '_skip', None) or cls._skip))
            continue
        xfail = getattr(f, '_xfail', False)
        STATE['lines'] = []
        STATE['bad'] = None
        failed = None
        for params in combos(f):
            try:
                if cls is None:
                    f(**params)
                else:
                    if hasattr(cls, 'setup_class'):
                        cls.setup_class()
                    inst = cls(mname) if issubclass(cls, unittest.TestCase) else cls()
                    getattr(inst, mname)(**params)
            except Exception as e:  # noqa: BLE001
                failed = failed or '%s: %s' % (type(e).__name__, e)
        if failed and not xfail:
            sys.stderr.write('FAILED %s: %s\n' % (title, failed))
        if STATE['bad']:
            sys.stderr.write('HAND %s (%s)\n' % (title, STATE['bad']))
            continue
        if not STATE['lines']:
            sys.stderr.write('NOCALLS %s\n' % title)
            continue
        name = title + (' (xfail upstream; pins reference behaviour)' if xfail else '')
        H.emit_test(out, name, STATE['lines'])


out = []
run(tp, 'test_parser', out)
run(ti, 'test_isoparser', out)
print('// Generated by tools/gen_parser_upstream_tests.py from the upstream')
print('// dateutil tests and the vendored reference implementation; do not edit.')
print()
print('\n'.join(out), end='')
