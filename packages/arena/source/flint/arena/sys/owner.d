/// Target-specific owner identities used by the arena core.
module flint.arena.sys.owner;

@safe:

version (WebAssembly)
{
    // The browser target uses non-shared module memory and a single execution thread.
    private ulong ownerCounter;

    package(flint.arena) ulong nextOwner() nothrow @nogc
    {
        if (ownerCounter == ulong.max)
            return 0;
        return ++ownerCounter;
    }
}
else
{
    import core.atomic : MemoryOrder, atomicLoad, cas;

    private shared ulong ownerCounter;

    package(flint.arena) ulong nextOwner() nothrow @nogc
    {
        return issueOwner(ownerCounter);
    }

    private ulong issueOwner(ref shared ulong counter) nothrow @nogc
    {
        ulong seen = atomicLoad!(MemoryOrder.raw)(counter);
        while (seen != ulong.max)
        {
            if (cas!(MemoryOrder.raw, MemoryOrder.raw)(&counter, seen, seen + 1))
                return seen + 1;
            seen = atomicLoad!(MemoryOrder.raw)(counter);
        }
        return 0;
    }

    @("native owner IDs saturate without recycling")
    unittest
    {
        shared ulong counter;
        counter = ulong.max - 1;
        assert(issueOwner(counter) == ulong.max);
        assert(issueOwner(counter) == 0);
        assert(issueOwner(counter) == 0);
    }
}
