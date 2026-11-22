#!/usr/bin/env python3
"""Compile Mock and Expectation misuse fixtures and require the specific diagnostic."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PRELUDE = """module fixture;
import flint.test : Mock, MockMethod, expect;
@safe:
interface Base { int value() const @safe nothrow @nogc; }
interface OtherBase { int value() const @safe nothrow @nogc; }
interface Derived : Base, OtherBase { string value(in string key) @safe; void mark(ref int input) @safe; }
"""
MANY = "interface Wide { " + " ".join(f"int m{index}() @safe;" for index in range(65)) + " }\n"
CASES = (
    ("overload without explicit selection",
     "void f() { auto m = Mock!Derived.create(); m.returns!(Derived.value)(1); }",
     "select overloaded methods with MockMethod!(Interface, name, overload)"),
    ("overload selected from another interface",
     "void f() { auto m = Mock!Base.create(); m.returns!(MockMethod!(Derived, \"value\", 0))(1); }",
     "mock overload belongs to a different interface"),
    ("overload index out of range",
     "void f() { auto m = Mock!Derived.create(); m.returns!(MockMethod!(Derived, \"value\", 9))(1); }",
     "Mock overload index is out of range"),
    ("non-interface contract",
     "struct Plain { int value() @safe { return 0; } }\nvoid f() { auto m = Mock!Plain.create(); }",
     "Mock requires an interface"),
    ("return by ref",
     "interface Borrowed { ref int value() @safe; }\nvoid f() { auto m = Mock!Borrowed.create(); }",
     "unsupported mock method qualifiers on value"),
    ("scope/return borrowed result",
     "interface Lifetime { int* value() return scope @safe; }\nvoid f() { auto m = Mock!Lifetime.create(); }",
     "unsupported mock method qualifiers on value"),
    ("typesafe variadic",
     "interface Variadic { int sum(int[] values...) @safe; }\nvoid f() { auto m = Mock!Variadic.create(); }",
     "unsupported mock method qualifiers on sum"),
    ("C linkage",
     "interface Foreign { extern (C) int call(int input) @safe; }\nvoid f() { auto m = Mock!Foreign.create(); }",
     "unsupported mock method qualifiers on call"),
    ("out parameter",
     "interface Output { void read(out int value) @safe; }\nvoid f() { auto m = Mock!Output.create(); }",
     "mock parameters must be value, ref, or in"),
    ("lazy parameter",
     "interface Deferred { void run(lazy int value) @safe; }\nvoid f() { auto m = Mock!Deferred.create(); }",
     "mock parameters must be value, ref, or in"),
    ("more than 64 methods", MANY + "void f() { auto m = Mock!Wide.create(); }",
     "Mock supports up to 64 distinct methods"),
    ("wrong return value type",
     "void f() { auto m = Mock!Base.create(); m.returns!(Base.value)(\"text\"); }",
     "return value must match the mock method type"),
    ("void expectation on a value method",
     "void f() { auto m = Mock!Base.create(); m.expects!(Base.value)(); }",
     "expects requires a void method"),
    ("value expectation on a void method",
     "void f() { auto m = Mock!Derived.create(); m.returns!(Derived.mark)(1); }",
     "return value must match the mock method type"),
    ("method from an unrelated interface",
     "interface Unrelated { int value() @safe; }\n"
     "void f() { auto m = Mock!Unrelated.create(); m.returns!(Base.value)(1); }",
     "method is not in the mock interface"),
    ("GC interface method from @nogc code",
     "interface Allocating { int value() @safe nothrow; }\n"
     "int use(Allocating service) @safe nothrow @nogc { return service.value(); }\n"
     "void f() { auto m = Mock!Allocating.create(); cast(void) use(m.instance()); }",
     "cannot call non-@nogc function"),
    ("system interface method from @safe code",
     "interface Unsafe { int value() @system; }\n"
     "void f() @safe { auto m = Mock!Unsafe.create(); cast(void) m.instance().value(); }",
     "cannot call `@system` function"),
    ("boolean helpers on a non-boolean value",
     "void f() { expect(1).toBeTrue(); }",
     "no property `toBeTrue`"),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="flint-test-negative-") as temp:
        fixture = Path(temp) / "fixture.d"
        for name, source, diagnostic in CASES:
            fixture.write_text(PRELUDE + source + "\n")
            command = [args.compiler, "-c", "-o-", "-preview=dip1000",
                       "-I" + str(ROOT / "packages" / "test" / "source"), str(fixture)]
            result = subprocess.run(command, text=True, capture_output=True, timeout=60)
            output = result.stdout + result.stderr
            assert 0 < result.returncode < 128 and diagnostic in output, (name, result.returncode, output)
            assert not re.search(r"(?i)internal compiler error|segmentation fault", output), (name, output)
            print(name + " rejected")
        fixture.write_text(PRELUDE + "void f() { auto m = Mock!Derived.create(); "
                           "m.returns!(MockMethod!(Derived, \"value\", 0))(\"x\"); m.expects!(Derived.mark)(); }\n")
        command = [args.compiler, "-c", "-o-", "-preview=dip1000",
                   "-I" + str(ROOT / "packages" / "test" / "source"), str(fixture)]
        result = subprocess.run(command, text=True, capture_output=True, timeout=60)
        assert result.returncode == 0, ("positive control", result.stdout + result.stderr)
        print("positive control compiled")


if __name__ == "__main__":
    main()
