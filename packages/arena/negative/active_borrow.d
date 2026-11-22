/// Standalone regression for native moves and destruction of borrowed owners.
module flint.active_borrow;

import core.lifetime : move;
import flint.arena : Buffer, BufferPoolOptions, RequestArena, Status;
import flint.arena.sys.pool : BufferPool, PoolSlot;
import std.stdio : stdout, writeln;

@safe:

private enum Operation
{
    quiescent,
    moveSource,
    overwrite,
    destroyOwner
}

private bool accepts(ref scope RequestArena arena, Buffer handle) nothrow @nogc
{
    return arena.read(handle, (scope const(ubyte)[]) @safe nothrow @nogc {}) == Status.ok;
}

private int exerciseArena(Operation operation) @system
{
    auto backing = new ubyte[32];
    auto arena = RequestArena(backing);
    auto allocation = arena.allocate(4);
    if (!allocation.ok())
        return 10;

    const handle = allocation.value;
    if (operation == Operation.quiescent)
    {
        scope moved = move(arena);
        if (!accepts(moved, handle) || accepts(arena, handle))
            return 11;
        destroy!false(moved);
        return accepts(moved, handle) ? 12 : 0;
    }

    auto spareBacking = new ubyte[32];
    auto spare = RequestArena(spareBacking);
    immutable outcome = arena.write(handle, (scope ubyte[]) @safe nothrow @nogc {
        if (operation == Operation.moveSource)
            move(arena, spare);
        else if (operation == Operation.overwrite)
            move(spare, arena);
        else
            destroy(arena);
    });
    writeln("unexpected return from active arena operation: ", outcome);
    stdout.flush();
    return 13;
}

private int exercisePool(Operation operation) @system
{
    auto backing = new ubyte[32];
    auto slots = new PoolSlot[2];
    const options = BufferPoolOptions(16, 2);
    auto pool = BufferPool.create(backing, slots, options);
    if (!pool.ok())
        return 20;
    auto lease = pool.value.acquire();
    if (!lease.ok())
        return 21;

    if (operation == Operation.quiescent)
    {
        scope moved = move(pool.value);
        if (moved.release(lease.value) != Status.ok || pool.value.acquire().ok())
            return 22;
        destroy!false(moved);
        return moved.acquire().ok() ? 23 : 0;
    }

    auto spareBacking = new ubyte[32];
    auto spareSlots = new PoolSlot[2];
    auto spare = BufferPool.create(spareBacking, spareSlots, options);
    if (!spare.ok())
        return 24;

    immutable outcome = pool.value.withBlock(lease.value, (scope ubyte[]) @safe nothrow @nogc {
        if (operation == Operation.moveSource)
            move(pool.value, spare.value);
        else if (operation == Operation.overwrite)
            move(spare.value, pool.value);
        else
            destroy(pool.value);
    });
    writeln("unexpected return from active pool operation: ", outcome);
    stdout.flush();
    return 25;
}

/// Select one positive or isolated fail-fast case in a child process.
int main(string[] args) @system
{
    if (args.length != 3)
        return 100;

    Operation operation;
    switch (args[2])
    {
    case "quiescent":
        operation = Operation.quiescent;
        break;
    case "move":
        operation = Operation.moveSource;
        break;
    case "overwrite":
        operation = Operation.overwrite;
        break;
    case "destroy":
        operation = Operation.destroyOwner;
        break;
    default:
        return 101;
    }

    switch (args[1])
    {
    case "arena":
        return exerciseArena(operation);
    case "pool":
        return exercisePool(operation);
    default:
        return 102;
    }
}
