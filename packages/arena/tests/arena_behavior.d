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

private bool holds(ref scope RequestArena arena, Buffer handle, ubyte expected) nothrow @nogc
{
    bool same;
    immutable status = arena.read(handle, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        same = true;
        foreach (byteValue; bytes)
            same = same && byteValue == expected;
    });
    return status == Status.ok && same;
}

@("every outOfMemory path, including overflowing padding, preserves cursor, peak and live bytes")
unittest
{
    ubyte[4_200] backing;
    // An odd base address forces nonzero padding for every alignment above one.
    scope arena = RequestArena(backing[1 .. 4_101]);
    immutable capacity = arena.stats().capacity;
    auto live = arena.copyIn(cast(const(ubyte)[]) "live");
    assert(live.ok());
    auto tail = arena.allocate(capacity - 16, 1);
    assert(tail.ok());
    assert(arena.write(tail.value, (scope ubyte[] bytes) @safe nothrow @nogc { bytes[] = 0x5A; }) == Status.ok);
    immutable used = arena.stats().used;
    immutable remaining = capacity - used;
    assert(remaining > 0 && remaining < 16);

    void unchanged()
    {
        const stats = arena.stats();
        assert(stats.used == used && stats.peak == used && stats.capacity == capacity && stats.resets == 0);
        assert(holds(arena, tail.value, 0x5A));
        assert(arena.read(live.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
                assert(bytes == cast(const(ubyte)[]) "live");
            }) == Status.ok);
    }

    assert(arena.allocate(capacity + 1, 1).error.code == Status.outOfMemory);
    unchanged();
    foreach (alignment; [1, 2, 8, 16, 4096])
    {
        assert(arena.allocate(size_t.max, alignment).error.code == Status.outOfMemory);
        assert(arena.allocate(size_t.max - remaining + 1, alignment).error.code == Status.outOfMemory);
        unchanged();
    }
    // The padding to the next 4096-byte boundary alone exceeds the remaining bytes.
    assert(arena.allocate(1, 4096).error.code == Status.outOfMemory);
    unchanged();
    ubyte[16] large;
    assert(arena.copyIn(large[0 .. remaining + 1]).error.code == Status.outOfMemory);
    assert(arena.append(tail.value, large[]) == Status.outOfMemory);
    assert(tail.value.length() == capacity - 16);
    unchanged();

    // The exact remainder is still usable after every failure.
    auto exact = arena.allocate(remaining, 1);
    assert(exact.ok() && arena.stats().used == capacity);
    assert(arena.allocate(1, 1).error.code == Status.outOfMemory);
    assert(arena.reset() == Status.ok && arena.allocate(capacity, 1).ok());
}

@("reentrant writes, reset during write and empty slices keep the borrow consistent")
unittest
{
    ubyte[32] backing;
    scope arena = RequestArena(backing[]);
    auto block = arena.allocate(4, 1);
    auto empty = arena.allocate(0, 1);
    assert(block.ok() && empty.ok());

    size_t visits;
    assert(arena.write(block.value, (scope ubyte[] outer) @safe nothrow @nogc {
            ++visits;
            assert(arena.reset() == Status.conflict);
            assert(arena.write(block.value, (scope ubyte[] inner) @safe nothrow @nogc {
                ++visits;
                inner[1] = 9;
                assert(arena.reset() == Status.conflict);
                assert(arena.write(empty.value, (scope ubyte[] none) @safe nothrow @nogc {
                    ++visits;
                    assert(none.length == 0);
                }) == Status.ok);
            }) == Status.ok);
            assert(outer[1] == 9);
            outer[0] = 7;
            assert(arena.reset() == Status.conflict);
        }) == Status.ok);
    assert(visits == 3);
    assert(arena.stats().resets == 0 && arena.stats().used == 4);

    // A zero-length handle stays valid after later allocations and expires with its epoch.
    assert(arena.allocate(8, 8).ok());
    assert(arena.read(empty.value, (scope const(ubyte)[] none) @safe nothrow @nogc {
            assert(none.length == 0);
        }) == Status.ok);
    assert(arena.reset() == Status.ok);
    assert(arena.reset() == Status.ok);
    foreach (stale; [block.value, empty.value])
        assert(arena.write(stale, (scope ubyte[]) @safe nothrow @nogc {
                assert(0, "stale handle entered the visitor");
            }) == Status.invalidArgument);
    assert(arena.stats().resets == 2);
}

@("poisoned and reused backing never exposes a previous request, and handles stay bound to their arena")
unittest
{
    ubyte[512] backing;
    backing[] = 0xA5;
    uint random = 0x0dd_ba11;
    Buffer previous;
    {
        scope first = RequestArena(backing[]);
        auto copied = first.copyIn(backing[0 .. 40]);
        assert(copied.ok() && holds(first, copied.value, 0xA5));
        auto fresh = first.allocate(64, 16);
        assert(fresh.ok() && holds(first, fresh.value, 0));
        assert(first.append(fresh.value, backing[100 .. 200]) == Status.ok);

        foreach (cycle; 0 .. 64)
        {
            // Each request fills everything it obtains with a request-specific pattern.
            immutable secret = cast(ubyte)(0x10 + cycle);
            while (true)
            {
                random ^= random << 13;
                random ^= random >>> 17;
                random ^= random << 5;
                auto block = first.allocate(random % 97, cast(size_t) 1 << (random >> 8) % 7);
                if (!block.ok())
                    break;
                assert(holds(first, block.value, 0));
                assert(first.write(block.value, (scope ubyte[] bytes) @safe nothrow @nogc {
                        bytes[] = secret;
                    }) == Status.ok);
                previous = block.value;
            }
            assert(first.reset() == Status.ok);
            assert(!holds(first, previous, secret));
        }
    }

    // A new arena over the same, still-poisoned bytes clears what it hands out.
    ubyte[512] otherBacking;
    scope reused = RequestArena(backing[]);
    scope other = RequestArena(otherBacking[]);
    auto whole = reused.allocate(backing.length, 1);
    assert(whole.ok() && holds(reused, whole.value, 0));
    assert(reused.read(previous, (scope const(ubyte)[]) @safe nothrow @nogc {
            assert(0, "a retired arena handle was accepted at the same address");
        }) == Status.invalidArgument);

    // Same epoch, offset and length in two arenas: identity alone decides.
    assert(reused.reset() == Status.ok && other.reset() == Status.ok);
    auto mine = reused.allocate(8, 8);
    auto theirs = other.allocate(8, 8);
    assert(mine.ok() && theirs.ok());
    immutable used = reused.stats().used;
    bool entered;
    scope reader = (scope const(ubyte)[]) @safe nothrow @nogc { entered = true; };
    scope writer = (scope ubyte[]) @safe nothrow @nogc { entered = true; };
    assert(reused.read(theirs.value, reader) == Status.invalidArgument);
    assert(reused.write(theirs.value, writer) == Status.invalidArgument);
    assert(other.read(mine.value, reader) == Status.invalidArgument);
    assert(other.write(mine.value, writer) == Status.invalidArgument);
    auto foreignTail = theirs.value;
    assert(reused.append(foreignTail, cast(const(ubyte)[]) "x") == Status.invalidArgument);
    assert(!entered && foreignTail.length() == 8 && reused.stats().used == used);
}
