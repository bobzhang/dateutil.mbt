"""No-op freezegun stand-in (only used to import upstream test modules)."""


def freeze_time(*args, **kwargs):
    def deco(f):
        return f
    return deco
