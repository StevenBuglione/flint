module betterc_arena;
import flint.arena : RequestArena, Status;

@safe:
/// Standalone BetterC allocator and stale-handle behavior test.
private int behaviorTest() nothrow @nogc
{
    ubyte[128] storage;
    scope arena = RequestArena(storage[]);
    auto block = arena.allocate(8);
    assert(block.ok());
    assert(arena.write(block.value, (scope ubyte[] bytes) @safe nothrow @nogc { bytes[0] = 7; }) == Status.ok);
    assert(arena.read(block.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(bytes[0] == 7);
        }) == Status.ok);
    assert(arena.reset() == Status.ok);
    assert(arena.read(block.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(bytes.length == 8);
        }) != Status.ok);
    return 0;
}

version (WebAssembly)
{
    /// Execute the real package assertions from a freestanding wasm32 host.
    extern (C) export int flint_test() nothrow @nogc
    {
        return behaviorTest();
    }
}
else
{
    extern (C) int main() nothrow @nogc
    {
        return behaviorTest();
    }
}
