#!/usr/bin/env python3
"""Run the arena compile-negative fixtures and the isolated lifetime fail-fast fixture with DMD or LDC."""
import argparse
from pathlib import Path
import re
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SHARED = ROOT / "tests" / "compile"
# (fixture, specific diagnostic). The shared tests/compile fixtures are also run by `tools/ci.py check --gate safety`.
NEGATIVES = (
    (SHARED / "escape_storage.d",
     r"escaping a reference to local variable `backing` by returning .* is not allowed in a `@safe` function"),
    (HERE / "escape_parameter.d",
     r"scope parameter `backing` may not be returned"),
    (SHARED / "escape_borrow.d",
     r"assigning scope variable `bytes` to global variable `leaked` is not allowed in a `@safe` function"),
    (HERE / "escape_write.d",
     r"assigning scope variable `bytes` to global variable `retained` is not allowed in a `@safe` function"),
    (HERE / "callback_gc.d", r"`@nogc` delegate `callback_gc\.rejectAllocation\.[^`]*` cannot call non-@nogc function "
     r"`callback_gc\.gcAllocation`"),
    (SHARED / "forge_buffer.d", r"constructor `flint\.arena\.Buffer\.this` .* is not accessible"),
)
POSITIVE = """module fixture;
import flint.arena : RequestArena, Status;
@safe:
Status fill() nothrow @nogc
{
    ubyte[64] backing;
    scope RequestArena arena = RequestArena(backing[]);
    auto block = arena.allocate(8);
    if (!block.ok())
        return block.error.code;
    ubyte last;
    immutable status = arena.write(block.value, (scope ubyte[] bytes) @safe nothrow @nogc { bytes[] = 1; last = bytes[$ - 1]; });
    return status == Status.ok && last == 1 ? arena.reset() : Status.conflict;
}
"""
# haltActiveBorrow aborts: the borrowed owner must die with SIGABRT before its visitor can return.
LIFETIME = (("quiescent", 0), ("move", -signal.SIGABRT), ("overwrite", -signal.SIGABRT),
            ("destroy", -signal.SIGABRT))


def compile_check(compiler, source):
    imports = "-I" + str(ROOT / "packages" / "arena" / "source")
    result = subprocess.run([compiler, "-c", "-o-", "-preview=dip1000", imports, str(source)],
                            text=True, capture_output=True, timeout=120)
    return result.returncode, result.stdout + result.stderr


def lifetime(compiler, directory):
    executable = Path(directory) / "active_borrow"
    for build in (["-g"], ["-O", "-release"] if Path(compiler).name.startswith("dmd") else ["-O2", "-release"]):
        command = [compiler, "-preview=dip1000", *build, "-I" + str(ROOT / "packages" / "arena" / "source"),
                   "-i=flint.arena", str(HERE / "active_borrow.d"), "-of=" + str(executable)]
        built = subprocess.run(command, text=True, capture_output=True, timeout=300)
        assert built.returncode == 0, ("active_borrow build", built.stdout + built.stderr)
        for owner in ("arena", "pool"):
            for operation, expected in LIFETIME:
                result = subprocess.run([str(executable), owner, operation], text=True, capture_output=True,
                                        timeout=60)
                output = result.stdout + result.stderr
                label = " ".join(("lifetime", owner, operation, *build))
                assert result.returncode == expected, (label, result.returncode, output)
                assert "unexpected return" not in output, (label, output)
                print(label + " ok (" + str(result.returncode) + ")")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler")
    args = parser.parse_args()
    for source, diagnostic in NEGATIVES:
        code, output = compile_check(args.compiler, source)
        assert 0 < code < 128, (source.name, code, output)
        assert re.search(diagnostic, output), (source.name, output)
        assert not re.search(r"(?i)internal compiler error|segmentation fault", output), (source.name, output)
        print(source.name + " rejected")
    with tempfile.TemporaryDirectory(prefix="flint-arena-negative-") as temp:
        positive = Path(temp) / "fixture.d"
        positive.write_text(POSITIVE)
        code, output = compile_check(args.compiler, positive)
        assert code == 0, ("positive control", output)
        print("positive control compiled")
        lifetime(args.compiler, temp)


if __name__ == "__main__":
    main()
