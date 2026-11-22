/// Reading what an ELF64 executable needs at run time: its interpreter, shared libraries and run path.
module flint_tool.support.elf;

@safe:

/// The dynamic-linking facts of one executable.
struct ElfFacts
{
    /// The file is a little-endian ELF64 executable or shared object.
    bool valid;
    /// Why it is not.
    string problem;
    /// e_machine (62 is x86-64, 183 is AArch64).
    uint machine;
    /// ET_DYN: position independent.
    bool positionIndependent;
    /// The PT_INTERP path, or empty for static executables.
    string interpreter;
    /// DT_NEEDED entries.
    string[] needed;
    /// DT_RUNPATH (or DT_RPATH).
    string runPath;
    /// A PT_GNU_RELRO segment is present.
    bool relro;
    /// DF_BIND_NOW or DF_1_NOW is set.
    bool bindNow;

    /// No interpreter and no shared libraries.
    bool fullyStatic() const
    {
        return valid && interpreter.length == 0 && needed.length == 0;
    }
}

/// Inspect ELF bytes.
ElfFacts inspectElf(scope const(ubyte)[] data)
{
    ElfFacts facts;
    if (data.length < 64 || data[0 .. 4] != [0x7f, 'E', 'L', 'F'] || data[4] != 2 || data[5] != 1)
    {
        facts.problem = "not a little-endian ELF64 file";
        return facts;
    }
    const type = u16(data, 16);
    facts.machine = u16(data, 18);
    facts.positionIndependent = type == 3;
    const phoff = u64(data, 32);
    const phentsize = u16(data, 54);
    const phnum = u16(data, 56);
    if (phentsize != 56 || phoff + phentsize * phnum > data.length)
    {
        facts.problem = "malformed program-header table";
        return facts;
    }
    ulong dynamicOffset;
    ulong dynamicSize;
    foreach (index; 0 .. phnum)
    {
        const base = cast(size_t)(phoff + index * phentsize);
        const kind = u32(data, base);
        const offset = u64(data, base + 8);
        const size = u64(data, base + 32);
        if (offset + size > data.length)
        {
            facts.problem = "segment outside the file";
            return facts;
        }
        if (kind == 3)
            facts.interpreter = cString(data, cast(size_t) offset);
        else if (kind == 2)
        {
            dynamicOffset = offset;
            dynamicSize = size;
        }
        else if (kind == 0x6474e552)
            facts.relro = true;
    }
    facts.valid = true;
    if (dynamicSize)
        readDynamic(data, dynamicOffset, dynamicSize, facts);
    return facts;
}

private void readDynamic(scope const(ubyte)[] data, ulong offset, ulong size, ref ElfFacts facts)
{
    ulong[] needed;
    ulong runPath = ulong.max;
    ulong stringTable;
    for (ulong position = offset; position + 16 <= offset + size; position += 16)
    {
        const tag = u64(data, cast(size_t) position);
        const value = u64(data, cast(size_t) position + 8);
        if (tag == 0)
            break;
        if (tag == 1)
            needed ~= value;
        else if (tag == 5)
            stringTable = value;
        else if (tag == 15 || tag == 29)
            runPath = value;
        else if ((tag == 30 && (value & 8)) || (tag == 0x6ffffffb && (value & 1)))
            facts.bindNow = true;
    }
    const strings = fileOffset(data, stringTable);
    foreach (name; needed)
        facts.needed ~= cString(data, cast(size_t)(strings + name));
    if (runPath != ulong.max)
        facts.runPath = cString(data, cast(size_t)(strings + runPath));
}

/// The file offset of virtual address `address`, through the PT_LOAD segments.
private ulong fileOffset(scope const(ubyte)[] data, ulong address)
{
    const phoff = u64(data, 32);
    foreach (index; 0 .. u16(data, 56))
    {
        const base = cast(size_t)(phoff + index * 56);
        if (u32(data, base) != 1)
            continue;
        const offset = u64(data, base + 8);
        const virtual = u64(data, base + 16);
        const size = u64(data, base + 32);
        if (address >= virtual && address < virtual + size)
            return address - virtual + offset;
    }
    return address;
}

private string cString(scope const(ubyte)[] data, size_t offset)
{
    size_t end = offset;
    while (end < data.length && data[end] != 0)
        end++;
    return offset < data.length ? (cast(const(char)[]) data[offset .. end]).idup : null;
}

private uint u16(scope const(ubyte)[] data, size_t at)
{
    return data[at] | (data[at + 1] << 8);
}

private uint u32(scope const(ubyte)[] data, size_t at)
{
    return u16(data, at) | (u16(data, at + 2) << 16);
}

private ulong u64(scope const(ubyte)[] data, size_t at)
{
    return u32(data, at) | (cast(ulong) u32(data, at + 4) << 32);
}
