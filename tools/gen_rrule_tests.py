#!/usr/bin/env python3
"""Translate upstream tests/test_rrule.py into MoonBit black-box tests.

Usage (from the repo root, with .repos symlinked):
    python3 tools/gen_rrule_tests.py

Each upstream test method becomes `test "<Class>.<method>" { ... }` in
rrule/upstream_*_test.mbt. The translation is a small AST-to-MoonBit compiler
for the subset of Python used by the test module; methods it cannot
translate are listed on stderr and are ported by hand in
rrule/upstream_manual_test.mbt (or skipped, see rrule/PORTING.md).
"""
import ast
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, ".repos/dateutil/tests/test_rrule.py")

FREQS = {
    "YEARLY": "Yearly", "MONTHLY": "Monthly", "WEEKLY": "Weekly",
    "DAILY": "Daily", "HOURLY": "Hourly", "MINUTELY": "Minutely",
    "SECONDLY": "Secondly",
}
WDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
LIST_KW = {"bysetpos", "bymonth", "bymonthday", "byyearday", "byeaster",
           "byweekno", "byhour", "byminute", "bysecond"}

# Methods translated by hand (or skipped); see PORTING.md.
MANUAL = {
    "testLongIntegers", "testToStrLongIntegers",  # Python 2 only
    "testBadUntilCountRRule",  # DeprecationWarning only
    "testCachePostInternal", "testSetCachePostInternal",  # private _cache
    "testStrWithTZID", "testStrWithTZIDMapping", "testStrWithTZIDCallable",
    "testStrWithTZIDCallableFailure", "testStrWithConflictingTZID",
    "testStrSetExDateWithTZID", "testStrSetExDateValueDateTimeWithTZID",
    "testStrUntilMustBeUTC", "testStrUntilWithTZ",
    "testSetRRuleCount", "testSetRDateCount", "testSetExRuleCount",
    "testSetExDateCount",
}


class Untranslatable(Exception):
    pass


def mbt_str(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20:
            out.append("\\u{%x}" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def const_int(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, int) \
            and not isinstance(node.value, bool):
        return node.value
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
        v = const_int(node.operand)
        return -v if isinstance(node.op, ast.USub) else v
    raise Untranslatable("int expected: " + ast.dump(node))


def tr_weekday(node):
    if isinstance(node, ast.Name) and node.id in WDAYS:
        return "@rrule." + node.id.lower()
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
            and node.func.id in WDAYS and len(node.args) == 1:
        return "@rrule.nth(@rrule.%s, %d)" % (node.func.id.lower(),
                                             const_int(node.args[0]))
    try:
        return "@rrule.weekdays[%d]" % const_int(node)
    except Untranslatable:
        raise Untranslatable("weekday expected: " + ast.dump(node))


def seq(node):
    if isinstance(node, (ast.Tuple, ast.List)):
        return node.elts
    return [node]


def tr_datetime(node):
    """datetime(...) / date(...) -> MoonBit expression."""
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)):
        raise Untranslatable("datetime expected")
    if node.func.id == "date":
        a = [const_int(x) for x in node.args]
        return "date(%d, %d, %d)" % tuple(a)
    if node.func.id != "datetime":
        raise Untranslatable("datetime expected: " + node.func.id)
    if node.keywords:
        raise Untranslatable("datetime kwargs")
    a = [const_int(x) for x in node.args]
    out = "dt(%d, %d, %d" % tuple(a[:3])
    labels = ["h", "mi", "s", "us"]
    for lab, v in zip(labels, a[3:]):
        if v != 0:
            out += ", %s=%d" % (lab, v)
    return out + ")"


def tr_rrule_call(node):
    if not node.args:
        raise Untranslatable("rrule without freq")
    freq = node.args[0]
    if not (isinstance(freq, ast.Name) and freq.id in FREQS):
        raise Untranslatable("freq")
    parts = [FREQS[freq.id]]
    kws = list(node.keywords)
    for kw in kws:
        name, v = kw.arg, kw.value
        if name is None:  # **dict(...)
            if isinstance(v, ast.Call) and isinstance(v.func, ast.Name) \
                    and v.func.id == "dict":
                kws.extend(v.keywords)
                continue
            raise Untranslatable("**kwargs")
        parts.append(name + "=" + tr_kwarg(name, v))
    return "@rrule.Rrule::new(" + ", ".join(parts) + ")"


def tr_kwarg(name, v):
    if name in LIST_KW:
        return "[" + ", ".join(str(const_int(x)) for x in seq(v)) + "]"
    if name == "byweekday":
        return "[" + ", ".join(tr_weekday(x) for x in seq(v)) + "]"
    if name == "wkst":
        return tr_weekday(v)
    if name in ("dtstart", "until"):
        return tr_datetime(v)
    if name in ("count", "interval"):
        return str(const_int(v))
    if name in ("cache", "inc", "unfold", "forceset", "compatible", "ignoretz"):
        if isinstance(v, ast.Constant) and isinstance(v.value, bool):
            return "true" if v.value else "false"
    raise Untranslatable("kwarg " + name)


def str_const(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return str_const(node.left) + str_const(node.right)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
            and node.func.attr == "join" and isinstance(node.func.value, ast.Constant):
        return node.func.value.value.join(str_const(x) for x in node.args[0].elts)
    raise Untranslatable("string expected")


class Ctx:
    def __init__(self):
        self.env = {}  # python name -> (mbt expr, kind)


def tr(node, ctx):
    """Translate an expression. Returns (code, kind); kind in
    {'rule', 'base', 'array', 'opt', 'iter', 'value'}."""
    if isinstance(node, ast.Name):
        if node.id in ctx.env:
            return node.id, ctx.env[node.id]
        if node.id in WDAYS:
            return "@rrule." + node.id.lower(), "value"
        raise Untranslatable("name " + node.id)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool):
            return ("true" if node.value else "false"), "value"
        if node.value is None:
            return "None", "value"
        if isinstance(node.value, int):
            return str(node.value), "value"
        if isinstance(node.value, str):
            return mbt_str(node.value), "value"
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        return str(const_int(node)), "value"
    if isinstance(node, (ast.List, ast.Tuple)):
        items = [tr(x, ctx)[0] for x in node.elts]
        return "[" + ", ".join(items) + "]", "array"
    if isinstance(node, ast.Call):
        f = node.func
        if isinstance(f, ast.Name):
            if f.id == "rrule":
                return tr_rrule_call(node), "rule"
            if f.id in ("datetime", "date"):
                return tr_datetime(node), "value"
            if f.id == "list":
                inner, kind = tr(node.args[0], ctx)
                if kind in ("rule", "base", "set"):
                    return inner + ".to_array()", "array"
                if kind == "iter":
                    return inner + ".to_array()", "array"
                if kind == "array":
                    return inner, "array"
                raise Untranslatable("list of " + kind)
            if f.id == "str":
                inner, kind = tr(node.args[0], ctx)
                if kind in ("rule",):
                    return inner + ".to_string()", "value"
                if kind == "base":
                    return inner + ".as_rrule().unwrap().to_string()", "value"
                raise Untranslatable("str of " + kind)
            if f.id == "rruleset":
                kws = [kw.arg + "=" + tr_kwarg(kw.arg, kw.value) for kw in node.keywords]
                return "@rrule.RruleSet::new(" + ", ".join(kws) + ")", "set"
            if f.id == "rrulestr":
                a0 = node.args[0]
                if isinstance(a0, ast.Name) and ctx.env.get(a0.id) == "str":
                    s = a0.id
                else:
                    s = mbt_str(str_const(a0))
                kws = []
                for kw in node.keywords:
                    kws.append(kw.arg + "=" + tr_kwarg(kw.arg, kw.value))
                return "@rrule.rrulestr(" + ", ".join([s] + kws) + ")", "base"
            if f.id == "isinstance":
                inner, kind = tr(node.args[0], ctx)
                cls = node.args[1].id
                if cls == "rrule":
                    return "(%s is Rule(_))" % inner, "value"
                if cls == "rruleset":
                    return "(%s is Set(_))" % inner, "value"
            raise Untranslatable("call " + f.id)
        if isinstance(f, ast.Attribute):
            obj, kind = tr(f.value, ctx)
            if kind not in ("rule", "base", "set"):
                raise Untranslatable("method on " + kind)
            m = f.attr
            args = [tr(a, ctx)[0] for a in node.args]
            for kw in node.keywords:
                args.append(kw.arg + "=" + tr_kwarg(kw.arg, kw.value))
            call = "%s.%s(%s)" % (obj, m, ", ".join(args))
            if m in ("before", "after"):
                return call, "opt"
            if m == "xafter":
                return call, "iter"
            if m in ("between",):
                return call, "array"
            if m == "count":
                return call, "value"
            if m == "replace":
                # only by-rule replacement is used upstream
                args = []
                for kw in node.keywords:
                    v = tr_kwarg(kw.arg, kw.value)
                    args.append("%s=Some(%s)" % (kw.arg, v))
                return "%s.replace(%s)" % (obj, ", ".join(args)), "rule"
            raise Untranslatable("method " + m)
    if isinstance(node, ast.Subscript):
        obj, kind = tr(node.value, ctx)
        sl = node.slice
        if isinstance(sl, ast.Slice):
            args = []
            for lab, v in (("start", sl.lower), ("stop", sl.upper), ("step", sl.step)):
                if v is not None:
                    args.append("%s=%d" % (lab, const_int(v)))
            return "%s.slice(%s)" % (obj, ", ".join(args)), "array"
        return "%s.get(%d)" % (obj, const_int(sl)), "opt"
    if isinstance(node, ast.Compare) and len(node.ops) == 1:
        op = node.ops[0]
        if isinstance(op, (ast.In, ast.NotIn)):
            item = tr(node.left, ctx)[0]
            coll = tr(node.comparators[0], ctx)[0]
            e = "%s.contains(%s)" % (coll, item)
            return (e if isinstance(op, ast.In) else "!" + e), "value"
    raise Untranslatable("expr " + ast.dump(node)[:80])


def tr_assert_eq(a, b, ctx, ind):
    left, lk = tr(a, ctx)
    right, rk = tr(b, ctx)
    if lk == "opt" and right != "None":
        right = "Some(%s)" % right
    if rk == "opt" and left != "None":
        left = "Some(%s)" % left
    if lk == "iter":
        left += ".to_array()"
    return ind + "assert_eq(%s, %s)" % (left, right)


def is_value_error(node):
    return isinstance(node, ast.Name) and node.id == "ValueError"


def tr_stmt(st, ctx, ind="  "):
    out = []
    if isinstance(st, ast.Expr) and isinstance(st.value, ast.Constant):
        return []  # docstring
    if isinstance(st, ast.Expr) and isinstance(st.value, ast.Call):
        c = st.value
        f = c.func
        if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) \
                and f.value.id == "self":
            if f.attr == "assertEqual":
                return [tr_assert_eq(c.args[0], c.args[1], ctx, ind)]
            if f.attr == "assertNotEqual":
                l, _ = tr(c.args[0], ctx)
                r, _ = tr(c.args[1], ctx)
                return [ind + "assert_not_eq(%s, %s)" % (l, r)]
            if f.attr == "_rrulestr_reverse_test":
                return [ind + "rrulestr_reverse_test(%s)" % tr(c.args[0], ctx)[0]]
            if f.attr == "assertRaises" and is_value_error(c.args[0]):
                fn = c.args[1]
                if isinstance(fn, ast.Name) and fn.id == "rrule":
                    call = ast.Call(func=ast.Name(id="rrule"), args=c.args[2:],
                                    keywords=c.keywords)
                    return [ind + "expect_value_error(() => ignore(%s))" %
                            tr_rrule_call(call)]
                if isinstance(fn, ast.Name) and fn.id in ctx.env.get("__funcs__", {}):
                    return [ind + "expect_value_error(() => %s())" % fn.id]
            raise Untranslatable("self." + f.attr)
    if isinstance(st, ast.Expr) and isinstance(st.value, ast.Call) \
            and isinstance(st.value.func, ast.Attribute) \
            and isinstance(st.value.func.value, ast.Name) \
            and ctx.env.get(st.value.func.value.id) == "set" \
            and st.value.func.attr in ("rrule", "rdate", "exrule", "exdate"):
        c = st.value
        return [ind + "%s.%s(%s)" % (c.func.value.id, c.func.attr, tr(c.args[0], ctx)[0])]
    if isinstance(st, ast.Assign) and len(st.targets) == 1 \
            and isinstance(st.targets[0], ast.Name):
        try:
            sv = str_const(st.value)
            ctx.env[st.targets[0].id] = "str"
            return [ind + "let %s = %s" % (st.targets[0].id, mbt_str(sv))]
        except Untranslatable:
            pass
        code, kind = tr(st.value, ctx)
        name = st.targets[0].id
        ctx.env[name] = kind
        return [ind + "let %s = %s" % (name, code)]
    if isinstance(st, ast.For) and isinstance(st.body[0], ast.Pass):
        coll, kind = tr(st.iter, ctx)
        return [ind + "for _ in %s.iter() {\n%s\n%s}" % (coll, ind + "  ", ind)]
    if isinstance(st, ast.Assert) and isinstance(st.test, ast.Compare) \
            and isinstance(st.test.ops[0], ast.Eq):
        return [tr_assert_eq(st.test.left, st.test.comparators[0], ctx, ind)]
    if isinstance(st, ast.With):
        item = st.items[0].context_expr
        if isinstance(item, ast.Call) and isinstance(item.func, ast.Attribute) \
                and item.func.attr in ("assertRaises", "raises") \
                and is_value_error(item.args[0]):
            body = []
            for s in st.body:
                if isinstance(s, ast.Assign):
                    body.append("ignore(" + tr(s.value, ctx)[0] + ")")
                elif isinstance(s, ast.Expr):
                    body.append("ignore(" + tr(s.value, ctx)[0] + ")")
                else:
                    raise Untranslatable("with body")
            return [ind + "expect_value_error(() => { %s })" % "; ".join(body)]
    if isinstance(st, ast.FunctionDef):
        # local helper used with assertRaises
        body = []
        for s in st.body:
            if isinstance(s, ast.Expr):
                body.append("ignore(" + tr(s.value, ctx)[0] + ")")
            else:
                raise Untranslatable("local def body")
        ctx.env.setdefault("__funcs__", {})[st.name] = True
        return [ind + "fn %s() raise {\n%s  %s\n%s}" % (
            st.name, ind, ("\n" + ind + "  ").join(body), ind)]
    if isinstance(st, ast.If):
        raise Untranslatable("if")
    raise Untranslatable("stmt " + ast.dump(st)[:80])


HEADER = """// GENERATED by tools/gen_rrule_tests.py from upstream tests/test_rrule.py.
// Do not edit by hand; re-run the generator instead.
"""


def main():
    tree = ast.parse(open(SRC).read())
    files = {"upstream_rrule_test.mbt": [], "upstream_tostr_test.mbt": [],
             "upstream_rrulestr_test.mbt": [], "upstream_rruleset_test.mbt": []}
    failed = []
    for cls in tree.body:
        if not isinstance(cls, ast.ClassDef):
            continue
        for fn in cls.body:
            if not (isinstance(fn, ast.FunctionDef) and fn.name.startswith("test")):
                continue
            if fn.name in MANUAL:
                failed.append((cls.name, fn.name, "manual"))
                continue
            ctx = Ctx()
            try:
                lines = []
                for st in fn.body:
                    lines.extend(tr_stmt(st, ctx))
            except Untranslatable as e:
                failed.append((cls.name, fn.name, str(e)))
                continue
            block = '///|\ntest "%s.%s" {\n%s\n}\n' % (cls.name, fn.name, "\n".join(lines))
            if cls.name == "RRuleSetTest":
                files["upstream_rruleset_test.mbt"].append(block)
            elif cls.name != "RRuleTest":
                failed.append((cls.name, fn.name, "class"))
            elif fn.name.startswith("testToStr"):
                files["upstream_tostr_test.mbt"].append(block)
            elif fn.name.startswith("testStr"):
                files["upstream_rrulestr_test.mbt"].append(block)
            else:
                files["upstream_rrule_test.mbt"].append(block)
    for name, blocks in files.items():
        with open(os.path.join(ROOT, "rrule", name), "w") as f:
            f.write(HEADER + "\n" + "\n".join(blocks))
    # keep the output stable under `moon fmt`
    subprocess.run(["moon", "fmt"], cwd=ROOT, check=False)
    n = sum(len(b) for b in files.values())
    print("translated %d tests" % n, file=sys.stderr)
    for c, m, why in failed:
        print("  not translated: %s.%s (%s)" % (c, m, why), file=sys.stderr)


if __name__ == "__main__":
    main()
