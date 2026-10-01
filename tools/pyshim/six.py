import sys, types, _thread as _t
PY2 = False
PY3 = True
string_types = (str,)
integer_types = (int,)
text_type = str
binary_type = bytes
advance_iterator = next
def raise_from(value, from_value):
    raise value from from_value
def add_metaclass(metaclass):
    def wrapper(cls):
        orig_vars = cls.__dict__.copy()
        slots = orig_vars.get('__slots__')
        if slots is not None:
            if isinstance(slots, str):
                slots = [slots]
            for slots_var in slots:
                orig_vars.pop(slots_var)
        orig_vars.pop('__dict__', None)
        orig_vars.pop('__weakref__', None)
        return metaclass(cls.__name__, cls.__bases__, orig_vars)
    return wrapper
moves = types.ModuleType("six.moves")
moves._thread = _t
moves.range = range
sys.modules["six.moves"] = moves
try:
    import winreg as _w
    moves.winreg = _w
except ImportError:
    pass


def assertRaisesRegex(self, *args, **kwargs):
    return self.assertRaisesRegex(*args, **kwargs)


def assertCountEqual(self, *args, **kwargs):
    return self.assertCountEqual(*args, **kwargs)


StringIO = __import__("io").StringIO
BytesIO = __import__("io").BytesIO
b = lambda s: s.encode("latin-1")
u = lambda s: s
iteritems = lambda d: iter(d.items())
