module slot_exchange;

import core.memory : GC;
import core.sync.semaphore : Semaphore;
import core.thread.osthread : Thread;
import flint.conc.slot : ProcessSlot;

@safe:

private interface Reading
{
    int value() const;
}

private extern (C++) interface ForeignReading
{
    int value() const;
}

private extern (Windows) interface IUnknown
{
    int query();
}

private interface ComReading : IUnknown
{
}

private final class Sample : Reading
{
    private int[] values;

    this(int value)
    {
        values = [value];
    }

    override int value() const
    {
        return values[0];
    }

    bool opEquals(const Sample other) const
    {
        return other !is null && value() == other.value();
    }

    override size_t toHash() const nothrow
    {
        return cast(size_t) values[0];
    }
}

private interface LeftReading : Reading
{
}

private interface RightReading : Reading
{
}

private final class DualReading : LeftReading, RightReading
{
    override int value() const
    {
        return 17;
    }
}

@("ProcessSlot compares identity and returns the actual witness")
unittest
{
    static assert(!is(ProcessSlot!int));
    static assert(!is(ProcessSlot!ForeignReading));
    static assert(!is(ProcessSlot!ComReading));
    static assert(!__traits(compiles, (ref shared ProcessSlot!Reading target, Object unrelated) {
            target.setVolatile(unrelated);
        }));

    shared ProcessSlot!Reading slot;
    auto first = new Sample(7);
    auto equal = new Sample(7);
    auto next = new Sample(9);
    assert(first.opEquals(equal) && first !is equal);
    assert(slot.getVolatile() is null);
    slot.setVolatile(first);
    assert(!slot.compareAndSet(equal, next));
    assert(slot.compareAndExchange(equal, next) is first);
    assert(slot.getVolatile() is first);
    assert(slot.compareAndExchange(first, null) is first);
    assert(slot.getVolatile() is null);
    assert(slot.compareAndSet(null, next));
    assert(slot.getAndSet(null) is next);
    assert(slot.getAndSet(first) is null);
    assert(slot.getVolatile() is first);
}

@("ProcessSlot exchanges return the previous reference in publication order")
@system unittest
{
    shared ProcessSlot!Sample slot;
    auto initial = new Sample(1);
    auto left = new Sample(2);
    auto right = new Sample(3);
    slot.setVolatile(initial);

    auto start = new Semaphore;
    Sample previousLeft, previousRight;
    auto first = new Thread({ start.wait(); previousLeft = slot.getAndSet(left); });
    auto second = new Thread({ start.wait(); previousRight = slot.getAndSet(right); });
    first.start();
    second.start();
    start.notify();
    start.notify();
    first.join();
    second.join();

    const published = slot.getVolatile();
    assert((published is right && previousLeft is initial && previousRight is left) || (published is left
            && previousRight is initial && previousLeft is right));
}

@("ProcessSlot uses object identity across two interface views")
unittest
{
    shared ProcessSlot!Reading slot;
    auto reading = new DualReading;
    Reading left = cast(LeftReading) reading;
    Reading right = cast(RightReading) reading;
    slot.setVolatile(left);
    assert(slot.compareAndSet(right, null));
    slot.setVolatile(right);
    assert(cast(Object) slot.compareAndExchange(left, null) is reading);
    assert(slot.getVolatile() is null);
}

private final class Publication
{
    shared ProcessSlot!Reading slot;
}

@system private Publication publishFromExitedThread()
{
    auto publication = new Publication;
    auto writer = new Thread({
        assert(publication.slot.compareAndExchange(null, new Sample(17)) is null);
    });
    writer.start();
    writer.join();
    return publication;
}

@("ProcessSlot strong CAS keeps the stored GC object and its data allocated")
@system unittest
{
    auto publication = publishFromExitedThread();
    GC.collect();
    auto retained = cast(Sample) publication.slot.getVolatile();
    assert(GC.query(cast(const(void)*) retained).base !is null);
    assert(GC.query(retained.values.ptr).base !is null);
    assert(retained.value() == 17);
    assert(publication.slot.getAndSet(null) is retained);
}
