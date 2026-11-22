module wasm_abi;
@safe:
private __gshared ubyte[56] bytes;
private void put16(ref ubyte[56] target, uint index, ushort value) nothrow @nogc
{
    target[index] = cast(ubyte) value;
    target[index + 1] = cast(ubyte) (value >> 8);
}
private void put32(ref ubyte[56] target, uint index, uint value) nothrow @nogc
{
    foreach (uint i; 0 .. 4) target[index + i] = cast(ubyte) (value >> (i * 8));
}
// SAFETY: Single-thread probe with fixed static storage; every field offset is inside the 56-byte fixture.
extern(C) export uint probe_build() nothrow @nogc @trusted
{
    bytes[] = 0;
    put32(bytes, 0, 0x544e4c46);
    put16(bytes, 4, 1);
    put32(bytes, 8, 56);
    put32(bytes, 12, 1);
    put32(bytes, 16, 1);
    put32(bytes, 20, 1);
    put16(bytes, 32, 2);
    put32(bytes, 36, 24);
    put32(bytes, 44, 1);
    put32(bytes, 48, 2);
    bytes[52] = '4'; bytes[53] = '2';
    return 56;
}
// SAFETY: wasm32 pointer fits uint and static storage remains live throughout the instance.
extern(C) export uint probe_pointer() nothrow @nogc @trusted
{
    static assert(size_t.sizeof == 4);
    return cast(uint) bytes.ptr;
}
