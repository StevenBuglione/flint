module flint_tool.support.elf_test;

import flint_tool.support.elf : inspectElf;
import flint.test : expect;

@safe:

@("non-ELF input is rejected, the running flint is a dynamic executable")
unittest
{
    import std.file : read, thisExePath;

    expect(inspectElf(cast(const(ubyte)[]) "not an elf").valid).toEqual(false);
    // A macOS flint is a Mach-O executable; packaging inspects ELF only (ADR-024).
    version (linux)
    {
        const facts = inspectElf(cast(const(ubyte)[]) read(thisExePath()));
        expect(facts.valid).toEqual(true);
        expect(facts.machine).toEqual(62);
        expect(facts.interpreter.length > 0).toEqual(true);
        expect(facts.fullyStatic()).toEqual(false);
    }
    else
        expect(inspectElf(cast(const(ubyte)[]) read(thisExePath())).valid).toEqual(false);
}
