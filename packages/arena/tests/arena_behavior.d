module arena_behavior;

import flint.arena : Buffer, RequestArena, Status;

@safe:

@("alignment is based on the actual backing address")
unittest
{
    ubyte[12_289] backing;
    scope arena = RequestArena(backing[1 .. $]);

    foreach (alignment; [1, 2, 8, 16, 4096])
    {
        auto allocation = arena.allocate(1, alignment);
        assert(allocation.ok());
        immutable status = arena.read(allocation.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert((cast(size_t) bytes.ptr & (alignment - 1)) == 0);
        });
        assert(status == Status.ok);
    }

    immutable used = arena.stats().used;
    foreach (alignment; [0, 3, 8192])
        assert(arena.allocate(1, alignment).error.code == Status.invalidArgument);
    assert(arena.stats().used == used);
}

@("capacity and padding checks leave arena usage intact on failure")
unittest
{
    ubyte[32] backing;
    scope arena = RequestArena(backing[]);
    assert(arena.allocate(backing.length + 1, 1).error.code == Status.outOfMemory);
    assert(arena.allocate(size_t.max, 4096).error.code == Status.outOfMemory);
    assert(arena.stats().used == 0);

    auto full = arena.allocate(backing.length, 1);
    assert(full.ok());
    assert(arena.allocate(0, 4096).ok());
    assert(arena.allocate(1, 4096).error.code == Status.outOfMemory);
    assert(arena.stats().capacity == backing.length);
    assert(arena.stats().peak == backing.length);
    assert(arena.stats().used == backing.length);
}

@("zero capacity accepts a valid empty handle")
unittest
{
    scope arena = RequestArena(null);
    auto empty = arena.allocate(0, 4096);
    assert(empty.ok());
    assert(empty.value.length() == 0);
    assert(arena.read(empty.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(bytes.length == 0);
        }) == Status.ok);
    assert(arena.allocate(1).error.code == Status.outOfMemory);
    assert(arena.copyIn(null).ok());
    assert(arena.stats().used == 0);
}

@("invalid, foreign and expired handles never enter the visitor")
unittest
{
    ubyte[16] firstBacking;
    ubyte[16] secondBacking;
    scope first = RequestArena(firstBacking[]);
    scope second = RequestArena(secondBacking[]);
    auto block = first.allocate(8);
    assert(block.ok());

    bool invoked;
    scope visitor = (scope const(ubyte)[]) @safe nothrow @nogc { invoked = true; };
    assert(first.read(Buffer.init, visitor) == Status.invalidArgument);
    assert(second.read(block.value, visitor) == Status.invalidArgument);
    assert(first.read(block.value, null) == Status.invalidArgument);
    assert(first.reset() == Status.ok);
    assert(first.reset() == Status.ok);
    assert(first.read(block.value, visitor) == Status.invalidArgument);
    assert(!invoked);
    assert(first.stats().used == 0);
    assert(first.stats().peak == 8);
    assert(first.stats().resets == 2);
}

@("nested read and write retain the active borrow until the outer visitor returns")
unittest
{
    ubyte[32] backing;
    scope arena = RequestArena(backing[]);
    auto block = arena.allocate(4);
    assert(block.ok());

    assert(arena.read(block.value, (scope const(ubyte)[] view) @safe nothrow @nogc {
            assert(arena.reset() == Status.conflict);
            assert(arena.write(block.value, (scope ubyte[] inner) @safe nothrow @nogc {
                assert(arena.reset() == Status.conflict);
                inner[0] = 12;
            }) == Status.ok);
            assert(view[0] == 12);
            assert(arena.reset() == Status.conflict);
        }) == Status.ok);
    assert(arena.reset() == Status.ok);
}

@("a new arena at the same backing address receives a unique owner")
unittest
{
    ubyte[32] backing;
    Buffer old;
    {
        scope arena = RequestArena(backing[]);
        auto block = arena.allocate(1, 1);
        assert(block.ok());
        old = block.value;
    }
    {
        scope arena = RequestArena(backing[]);
        assert(arena.allocate(1, 1).ok());
        assert(arena.read(old, (scope const(ubyte)[]) @safe nothrow @nogc {
                assert(0, "old owner unexpectedly accepted");
            }) == Status.invalidArgument);
    }
}

@("append joins parser fragments and preserves prefix handles and bounds on failure")
unittest
{
    align(8) ubyte[12] storage;
    ubyte[8] otherStorage;
    scope arena = RequestArena(storage[]);
    scope other = RequestArena(otherStorage[]);
    auto prefix = arena.copyIn([cast(ubyte) 'a']);
    assert(prefix.ok());
    auto joined = prefix.value;
    assert(arena.append(joined, cast(const(ubyte)[]) "bc") == Status.ok);
    assert(prefix.value.length() == 1 && joined.length() == 3);
    assert(arena.append(prefix.value, cast(const(ubyte)[]) "d") == Status.conflict);
    assert(other.append(joined, cast(const(ubyte)[]) "e") == Status.invalidArgument);
    assert(arena.append(joined, cast(const(ubyte)[]) "too many!!") == Status.outOfMemory);
    assert(arena.stats().used == 3 && arena.stats().peak == 3);
    assert(arena.read(joined, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(bytes == cast(const(ubyte)[]) "abc");
            assert(arena.append(joined, bytes) == Status.conflict);
        }) == Status.ok);
    assert(arena.append(joined, cast(const(ubyte)[]) "defghijkl") == Status.ok);
    assert(arena.stats().used == 12 && joined.length() == 12);
    assert(arena.reset() == Status.ok);
    assert(arena.append(joined, null) == Status.invalidArgument);
    auto empty = arena.allocate(0);
    assert(empty.ok() && arena.append(empty.value, cast(const(ubyte)[]) "x") == Status.ok);
    assert(empty.value.length() == 1);
}

@("allocation clears storage and copy-in preserves overlapping input")
unittest
{
    align(8) ubyte[32] backing;
    backing[4 .. 12] = [55, 66, 77, 88, 99, 110, 121, 132];
    scope arena = RequestArena(backing[]);
    assert(arena.allocate(1, 1).ok());

    auto copied = arena.copyIn(backing[6 .. 10]);
    assert(copied.ok());
    assert(arena.read(copied.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(bytes[0] == 77 && bytes[1] == 88 && bytes[2] == 99 && bytes[3] == 110);
        }) == Status.ok);

    assert(arena.reset() == Status.ok);
    auto zeroed = arena.allocate(32, 1);
    assert(zeroed.ok());
    assert(arena.read(zeroed.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            foreach (byteValue; bytes)
                assert(byteValue == 0);
        }) == Status.ok);
}

@("seeded allocation and reuse preserve bounds, identity and initialized bytes")
unittest
{
    ubyte[8_198] backing;
    scope arena = RequestArena(backing[3 .. $]);
    uint random = 0xb947_52ab;
    Buffer stale;

    foreach (size_t cycle; 0 .. 512)
    {
        foreach (size_t entry; 0 .. 24)
        {
            random ^= random << 13;
            random ^= random >>> 17;
            random ^= random << 5;
            immutable count = cast(size_t)(random % 385);
            immutable alignment = cast(size_t) 1 << ((random >> 12) % 13);
            immutable used = arena.stats().used;
            auto allocation = arena.allocate(count, alignment);
            if (!allocation.ok())
            {
                assert(allocation.error.code == Status.outOfMemory);
                assert(arena.stats().used == used);
                continue;
            }

            const block = allocation.value;
            assert(block.length() == count);
            assert(arena.read(block, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
                    if (bytes.length != 0)
                        assert((cast(size_t) bytes.ptr & (alignment - 1)) == 0);
                    foreach (byteValue; bytes)
                        assert(byteValue == 0);
                }) == Status.ok);
            assert(arena.write(block, (scope ubyte[] bytes) @safe nothrow @nogc {
                    bytes[] = cast(ubyte) random;
                }) == Status.ok);
            stale = block;
        }

        assert(arena.reset() == Status.ok);
        assert(arena.read(stale, (scope const(ubyte)[]) @safe nothrow @nogc {
                assert(0, "old epoch unexpectedly accepted");
            }) == Status.invalidArgument);
        assert(arena.stats().resets == cycle + 1);
    }
}
