/// Native per-core slab storage provisioned by the owning worker.
module flint.arena.sys.pool;

import flint.arena : BufferPoolOptions, Error, Result, Status;
import flint.arena.sys.borrow : haltActiveBorrow;
import flint.arena.sys.owner : nextOwner;

@safe:

version (WebAssembly)
{
}
else version (D_BetterC)
{
}
else
{
    private alias BlockVisitor = void delegate(scope ubyte[]) @safe nothrow @nogc;

    /// Metadata backing to provide alongside the slab bytes at startup.
    package(flint) struct PoolSlot
    {
        private size_t next = size_t.max;
        private ulong generation;
        private bool leased;
        private bool visiting;
    }

    /// Identifies one checkout from its owning pool and carries no pointer.
    package(flint) struct BufferLease
    {
        private ulong owner;
        private size_t index;
        private ulong generation;

        private this(ulong owner, size_t index, ulong generation) nothrow @nogc
        {
            this.owner = owner;
            this.index = index;
            this.generation = generation;
        }
    }

    /// A worker-local pool whose backing and metadata remain owned by its caller.
    package(flint) struct BufferPool
    {
        private ubyte[] backing;
        private PoolSlot[] slots;
        private size_t blockBytes;
        private size_t freeHead = size_t.max;
        private size_t activeBorrows;
        private ulong owner;

        @disable this(this);
        @disable void opAssign(BufferPool replacement);

        ~this() scope nothrow @nogc
        {
            if (activeBorrows != 0)
                haltActiveBorrow();
            owner = 0;
            freeHead = size_t.max;
        }

        /// D runtime moves may only transfer a quiescent pool.
        void opPostMove(scope const ref BufferPool original) scope nothrow @nogc
        {
            if (original.activeBorrows != 0)
                haltActiveBorrow();
        }

        /// Initialize a fixed pool over exclusive caller storage. No storage grows on checkout.
        static Result!BufferPool create(return scope ubyte[] backing, return scope PoolSlot[] slots,
                BufferPoolOptions options) nothrow @nogc
        {
            immutable blockBytes = options.blockBytes;
            immutable blockCount = options.blockCount;
            if (blockBytes == 0 || blockCount == 0 || blockCount > slots.length
                    || blockCount > backing.length / blockBytes)
            {
                return Result!BufferPool(BufferPool.init, Error(Status.invalidArgument,
                        "invalid pool capacity or backing"));
            }

            immutable owner = nextOwner();
            if (owner == 0)
                return Result!BufferPool(BufferPool.init, Error(Status.resourceExhausted, "pool identity exhausted"));

            return Result!BufferPool(BufferPool(backing[0 .. blockBytes * blockCount],
                    slots[0 .. blockCount], blockBytes, owner));
        }

        private this(return scope ubyte[] bytes, return scope PoolSlot[] slots, size_t stride, ulong id) nothrow @nogc
        {
            this.backing = bytes;
            this.slots = slots;
            this.blockBytes = stride;
            this.owner = id;
            foreach (index, ref slot; this.slots)
                slot = PoolSlot(index + 1);
            this.slots[$ - 1].next = size_t.max;
            freeHead = 0;
        }

        /// Obtain a zeroed block in constant list time, or signal exhaustion.
        Result!BufferLease acquire() scope nothrow @nogc
        {
            if (freeHead == size_t.max)
                return Result!BufferLease(BufferLease.init, Error(Status.resourceExhausted, "buffer pool exhausted"));

            immutable index = freeHead;
            scope slot = &slots[index];
            freeHead = slot.next;
            slot.leased = true;
            immutable offset = index * blockBytes;
            backing[offset .. offset + blockBytes] = 0;
            return Result!BufferLease(BufferLease(owner, index, slot.generation));
        }

        /// Present the leased bytes to a bounded scope, retaining the lease during the callback.
        Status withBlock(BufferLease lease, scope BlockVisitor visitor) scope nothrow @nogc
        {
            if (visitor is null || !valid(lease))
                return Status.invalidArgument;

            scope slot = &slots[lease.index];
            if (slot.visiting)
                return Status.conflict;

            slot.visiting = true;
            ++activeBorrows;
            scope (exit)
            {
                --activeBorrows;
                slot.visiting = false;
            }
            immutable offset = lease.index * blockBytes;
            visitor(backing[offset .. offset + blockBytes]);
            return Status.ok;
        }

        /// Return a block to its owner for reuse. A saturated generation retires the block.
        Status release(BufferLease lease) scope nothrow @nogc
        {
            if (!valid(lease))
                return Status.invalidArgument;

            scope slot = &slots[lease.index];
            if (slot.visiting)
                return Status.conflict;

            slot.leased = false;
            if (slot.generation != ulong.max)
            {
                ++slot.generation;
                slot.next = freeHead;
                freeHead = lease.index;
            }
            return Status.ok;
        }

        private bool valid(BufferLease lease) const scope nothrow @nogc
        {
            return owner != 0 && lease.owner == owner && lease.index < slots.length
                && slots[lease.index].leased && slots[lease.index].generation == lease.generation;
        }
    }

    @("slab leases enforce bounds, pool ownership and generation across reuse")
    unittest
    {
        ubyte[24] firstBacking;
        PoolSlot[2] firstSlots;
        ubyte[24] secondBacking;
        PoolSlot[2] secondSlots;
        auto options = BufferPoolOptions(12, 2);

        scope first = BufferPool.create(firstBacking[], firstSlots[], options);
        scope second = BufferPool.create(secondBacking[], secondSlots[], options);
        assert(first.ok() && second.ok());
        auto left = first.value.acquire();
        auto right = first.value.acquire();
        assert(left.ok() && right.ok());
        assert(first.value.acquire().error.code == Status.resourceExhausted);
        assert(second.value.release(left.value) == Status.invalidArgument);
        assert(first.value.release(BufferLease.init) == Status.invalidArgument);

        assert(first.value.withBlock(left.value, (scope ubyte[] block) @safe nothrow @nogc {
                assert(block.length == 12);
                block[] = 51;
                assert(first.value.release(left.value) == Status.conflict);
            }) == Status.ok);
        assert(first.value.release(left.value) == Status.ok);

        auto reused = first.value.acquire();
        assert(reused.ok());
        assert(first.value.release(left.value) == Status.invalidArgument);
        assert(first.value.withBlock(reused.value, (scope ubyte[] block) @safe nothrow @nogc {
                foreach (byteValue; block)
                    assert(byteValue == 0);
            }) == Status.ok);
        assert(first.value.release(reused.value) == Status.ok);
        assert(first.value.release(right.value) == Status.ok);
    }

    @("oversized pool requests fail and a saturated lease retires without reuse")
    unittest
    {
        ubyte[4] backing;
        PoolSlot[1] slots;
        assert(BufferPool.create(backing[], slots[], BufferPoolOptions(size_t.max, 2))
                .error.code == Status.invalidArgument);
        assert(BufferPool.create(backing[], slots[], BufferPoolOptions(0, 1)).error.code == Status.invalidArgument);
        scope pool = BufferPool.create(backing[], slots[], BufferPoolOptions(backing.length, slots.length));
        assert(pool.ok());

        pool.value.slots[0].generation = ulong.max;
        auto lease = pool.value.acquire();
        assert(lease.ok());
        assert(pool.value.release(lease.value) == Status.ok);
        assert(pool.value.release(lease.value) == Status.invalidArgument);
        assert(pool.value.acquire().error.code == Status.resourceExhausted);
    }
}
