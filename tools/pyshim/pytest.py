"""Minimal pytest stand-in so the upstream test modules can be imported
(for extracting their data tables) without installing pytest."""
import contextlib


class _Mark:
    def __getattr__(self, name):
        def deco(*args, **kwargs):
            if len(args) == 1 and callable(args[0]) and not kwargs:
                return args[0]
            return lambda f: f
        return deco


mark = _Mark()


def fixture(*args, **kwargs):
    if len(args) == 1 and callable(args[0]):
        return args[0]
    return lambda f: f


@contextlib.contextmanager
def raises(exc, *args, **kwargs):
    try:
        yield
    except exc:
        return
    raise AssertionError("did not raise")


def param(*args, **kwargs):
    return args
