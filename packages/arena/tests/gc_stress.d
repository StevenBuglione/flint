/++
A stress test of the Flint collector with a shadow check (owner decision b515505b): threads allocate across the
small bins, the thread caches' four attribute classes, finalized objects and large blocks while collections run.
Every object carries its owner's stamp and a fill pattern. Each thread keeps a random subset in a shadow ring and
linked nodes reachable only through those, and re-verifies all of them after every round. An object the collector
handed out twice, or freed while referenced, shows up as an overwritten stamp, a broken chain or a duplicate
address.

The test program runs on the Flint collector (tests/gc_selected.d sets `rt_options`).
+/
module flint.arena.gc_stress_test;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.memory : GC;
import core.thread : Thread;

@system:

private enum threads = 4;
private enum rounds = 24;
private enum perRound = 6_000;
private enum ringSize = 2_048;

/// A linked object with pointers and no destructor: the cache's class with no attributes.
private final class Node
{
    Node next;
    ulong stamp;
    ubyte[40] body;
}

/// A finalized object: the locked path.
private final class Finalized
{
    ulong stamp;
    static shared ulong finalized;

    ~this()
    {
        atomicOp!"+="(finalized, 1);
    }
}

/// What one retained object should hold.
private struct Shadow
{
    void[] block;
    ulong stamp;
    ubyte kind;
}

private ulong stampOf(size_t owner, size_t sequence)
{
    return (cast(ulong) owner << 48) ^ (sequence * 0x9E37_79B9_7F4A_7C15UL) | 1;
}

private ubyte fill(ulong stamp, size_t index)
{
    return cast(ubyte)((stamp >> (index % 7) * 8) ^ index);
}

private void writePattern(ubyte[] bytes, ulong stamp)
{
    if (bytes.length >= 8)
        *cast(ulong*) bytes.ptr = stamp;
    foreach (i; (bytes.length >= 8 ? 8 : 0) .. bytes.length)
        bytes[i] = fill(stamp, i);
}

private bool patternHolds(const(ubyte)[] bytes, ulong stamp)
{
    if (bytes.length >= 8 && *cast(const(ulong)*) bytes.ptr != stamp)
        return false;
    foreach (i; (bytes.length >= 8 ? 8 : 0) .. bytes.length)
        if (bytes[i] != fill(stamp, i))
            return false;
    return true;
}

/// A small deterministic generator per thread.
private struct Random
{
    ulong state;

    uint next()
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        return cast(uint) state;
    }
}

private shared bool failed;
private shared size_t verified;
private __gshared string failure;

private void fail(string why)
{
    if (!atomicLoad(failed))
    {
        failure = why;
        atomicStore(failed, true);
    }
}

/// One allocation of the kind `pick` selects, stamped; nodes are linked into `chain`.
private Shadow allocate(ulong stamp, uint pick, ref Node chain)
{
    Shadow shadow;
    shadow.stamp = stamp;
    shadow.kind = cast(ubyte)(pick % 6);
    final switch (shadow.kind)
    {
    case 0: // NO_SCAN | APPENDABLE, every small bin
        auto bytes = new ubyte[](1 + pick % 2_040);
        writePattern(bytes, stamp);
        shadow.block = bytes;
        break;
    case 1: // APPENDABLE with pointers
        auto pointers = new void*[](1 + pick % 200);
        pointers[0] = cast(void*) stamp;
        shadow.block = cast(void[]) pointers;
        break;
    case 2: // no attributes: a class with pointers, linked into the chain
        auto node = new Node;
        node.stamp = stamp;
        writePattern(node.body[], stamp);
        node.next = chain;
        chain = node;
        shadow.block = (cast(void*) node)[0 .. __traits(classInstanceSize, Node)];
        break;
    case 3: // NO_SCAN without APPENDABLE, through GC.malloc
        auto bytes = (cast(ubyte*) GC.malloc(16 + pick % 1_000, GC.BlkAttr.NO_SCAN))[0 .. 16 + pick % 1_000];
        writePattern(bytes, stamp);
        shadow.block = bytes;
        break;
    case 4: // finalized: the locked path
        auto object = new Finalized;
        object.stamp = stamp;
        shadow.block = (cast(void*) object)[0 .. __traits(classInstanceSize, Finalized)];
        break;
    case 5: // large: the locked big path
        auto bytes = new ubyte[](4_096 + pick % 20_000);
        writePattern(bytes, stamp);
        shadow.block = bytes;
        break;
    }
    return shadow;
}

/// Append to retained small arrays: APPENDABLE metadata must still describe them.
private void appendRetained(Shadow[] ring)
{
    foreach (ref shadow; ring)
    {
        if (shadow.kind != 0 || shadow.block.length == 0 || shadow.block.length > 512)
            continue;
        auto bytes = cast(ubyte[]) shadow.block;
        bytes ~= cast(ubyte) 0;
        bytes = bytes[0 .. $ - 1];
        if (!patternHolds(bytes, shadow.stamp))
            fail("an appended array lost its contents");
        shadow.block = bytes;
    }
}

/// Whether a retained object still holds what was written into it.
private bool holds(ref const Shadow shadow)
{
    final switch (shadow.kind)
    {
    case 0:
    case 3:
    case 5:
        return patternHolds(cast(const(ubyte)[]) shadow.block, shadow.stamp);
    case 1:
        return (cast(const(void*)[]) shadow.block)[0] == cast(void*) shadow.stamp;
    case 2:
        auto node = cast(Node) cast(Object) shadow.block.ptr;
        return node.stamp == shadow.stamp && patternHolds(node.body[], shadow.stamp);
    case 4:
        return (cast(Finalized) cast(Object) shadow.block.ptr).stamp == shadow.stamp;
    }
}

/// The shadow check: every retained object, and every node of the chain.
private void verify(const(Shadow)[] ring, Node chain)
{
    foreach (ref shadow; ring)
    {
        if (shadow.block.length == 0)
            continue;
        if (!holds(shadow))
            fail("a retained object was overwritten: freed while referenced or handed out twice");
        atomicOp!"+="(verified, 1);
    }
    for (auto node = chain; node !is null; node = node.next)
        if (!patternHolds(node.body[], node.stamp))
            fail("a node reachable only through the chain was overwritten");
}

/// One thread's work; the retained shadows are returned so the caller checks them again after the thread exits.
private Shadow[] work(size_t owner)
{
    auto random = Random(0x1234_5678 + owner * 7919);
    auto ring = new Shadow[ringSize];
    size_t ringNext, sequence;
    Node chain; // reachable only through this local and the ring
    foreach (round; 0 .. rounds)
    {
        foreach (_; 0 .. perRound)
        {
            const pick = random.next();
            const stamp = stampOf(owner, ++sequence);
            if (pick % 8 == 0)
                ring[ringNext++ % ringSize] = allocate(stamp, pick, chain);
            else
                cast(void) allocate(stamp, pick, chain);
            if (pick % 6_007 == 0)
                chain = null; // drop the chain: its nodes become garbage, except those the ring holds
        }
        appendRetained(ring);
        if (owner == 0 && round % 3 == 0)
            GC.collect();
        verify(ring, chain);
        if (atomicLoad(failed))
            break;
    }
    return ring;
}

/// The stress run: worker threads under collections from the main thread, then the shadow check after they exit.
private void stress(void delegate() alongside = null)
{
    Shadow[][threads] kept;
    Thread[threads] workers;
    foreach (i, ref worker; workers)
    {
        const owner = i;
        worker = new Thread(() { kept[owner] = work(owner); });
        worker.start();
    }
    // The main thread allocates and collects while the workers run.
    foreach (_; 0 .. 40)
    {
        auto garbage = new ubyte[](128);
        garbage[0] = 1;
        GC.collect();
        Thread.yield();
    }
    foreach (worker; workers)
        worker.join();
    if (alongside !is null)
        alongside();
    assert(!atomicLoad(failed), failure);

    // The workers exited with objects in their caches; their retained objects must survive more collections.
    GC.collect();
    GC.collect();
    bool[size_t] addresses;
    foreach (ring; kept)
        foreach (ref shadow; ring)
        {
            if (shadow.block.length == 0)
                continue;
            if (shadow.kind == 0 || shadow.kind == 3 || shadow.kind == 5)
                assert(patternHolds(cast(const(ubyte)[]) shadow.block, shadow.stamp),
                        "a retained object was lost after its thread exited");
            const address = cast(size_t) shadow.block.ptr;
            assert(address !in addresses, "two retained objects share an address");
            addresses[address] = true;
        }
    assert(atomicLoad(verified) > threads * rounds * ringSize / 2);
    assert(GC.profileStats().numCollections > 10);
}

@("Flint collector stress: threads, thread caches, finalizers and large blocks under collections; shadow check")
unittest
{
    stress();
}

private enum moved = 4_096;

/// Objects held only in two heap arrays, moved from one to the other without allocating while collections run.
private final class Mover
{
    Node[] left, right;
    shared bool stop;
    size_t passes;

    this()
    {
        left = new Node[moved];
        right = new Node[moved];
        foreach (i, ref slot; left)
        {
            slot = new Node;
            slot.stamp = stampOf(99, i);
            writePattern(slot.body[], slot.stamp);
        }
    }

    /// A marker that scanned `right` before an object moved there, and `left` after it left, has not seen it: only
    /// the rescan of the written page keeps it.
    void run()
    {
        while (!atomicLoad(stop))
        {
            foreach (i; 0 .. moved)
            {
                right[i] = left[i];
                left[i] = null;
            }
            foreach (i; 0 .. moved)
            {
                left[i] = right[i];
                right[i] = null;
            }
            ++passes;
        }
    }

    void check()
    {
        foreach (i; 0 .. moved)
        {
            auto node = left[i] is null ? right[i] : left[i];
            if (node is null || node.stamp != stampOf(99, i) || !patternHolds(node.body[], node.stamp))
                fail("an object moved between heap arrays while marking ran was freed");
        }
    }
}

@("D3 concurrent marking: the stress run and objects moved between heap arrays during marking survive")
unittest
{
    import flint.arena.gc : concurrentCollections, setConcurrentMarking;

    if (!setConcurrentMarking(true))
        return; // no soft-dirty tracking here: collections stop the world, which the test above covers
    scope (exit)
        cast(void) setConcurrentMarking(false);
    const before = concurrentCollections();
    auto mover = new Mover;
    auto thread = new Thread(&mover.run);
    thread.start();
    stress(() { atomicStore(mover.stop, true); thread.join(); mover.check(); });
    assert(concurrentCollections() - before > 10, "collections did not mark concurrently");
    assert(mover.passes > 0);
}
