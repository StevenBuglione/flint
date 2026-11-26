module atomic_reference_test;

import core.memory : GC;
import core.thread.osthread : Thread; // ADR-026 requires the declaring module on DMD for Windows.
import core.time : MonoTime;
import flint.java.util.concurrent.atomic.atomicreference : AtomicReference;

@safe:

private interface Reading
{
    int sum() const;
}

private extern (C++) interface ForeignReading
{
}

private final class Sample : Reading
{
    private int[] values;

    this(int value)
    {
        values = [value, value + 1];
    }

    override int sum() const
    {
        return values[0] + values[1];
    }
}

@("AtomicReference keeps the identity of nullable class and interface references")
unittest
{
    static assert(!is(AtomicReference!int));
    static assert(!is(AtomicReference!(const Sample)));
    static assert(!is(AtomicReference!(immutable Sample)));
    static assert(!is(AtomicReference!(shared Reading)));
    static assert(!is(AtomicReference!ForeignReading));
    auto sample = new Sample(3);
    auto reference = new AtomicReference!Sample(sample);
    assert(reference.getAcquire() is sample);
    reference.setRelease(null);
    assert(reference.getAcquire() is null);

    auto interfaceReference = new AtomicReference!Reading;
    assert(interfaceReference.getAcquire() is null);
    interfaceReference.lazySet(sample);
    assert(interfaceReference.getAcquire() is sample);
    assert(interfaceReference.getAcquire().sum() == 7);
}

@("AtomicReference publishes fully constructed values while a reader is active")
@system unittest
{
    auto reference = new AtomicReference!Reading;
    auto writer = new Thread(() { reference.lazySet(new Sample(20)); });
    writer.start();
    scope (exit)
        writer.join();

    const deadline = MonoTime.currTime.ticks + 5 * MonoTime.ticksPerSecond;
    Reading published;
    while ((published = reference.getAcquire()) is null)
    {
        assert(MonoTime.currTime.ticks < deadline, "spin exceeded publication timeout");
        Thread.yield();
    }
    assert(published.sum() == 41);
}

@system private AtomicReference!Reading publishFromExitedThread()
{
    auto reference = new AtomicReference!Reading;
    auto writer = new Thread(() { reference.setRelease(new Sample(21)); });
    writer.start();
    writer.join();
    return reference;
}

@("The publication slot keeps the reference and its owned data visible to the GC")
@system unittest
{
    auto reference = publishFromExitedThread();
    GC.collect();
    auto retained = cast(Sample) reference.getAcquire();
    assert(GC.query(cast(const(void)*) retained).base !is null);
    assert(GC.query(retained.values.ptr).base !is null);
    assert(retained.sum() == 43);
}

@("AtomicReference volatile operations return exact identities and witnesses")
unittest
{
    auto reference = new AtomicReference!Reading;
    auto first = new Sample(4);
    auto equal = new Sample(4);
    auto next = new Sample(5);
    assert(first.sum() == equal.sum() && first !is equal);
    assert(reference.get() is null);

    reference.set(first);
    assert(reference.getAcquire() is first);
    assert(!reference.compareAndSet(equal, next));
    assert(reference.compareAndExchange(equal, next) is first);
    assert(reference.get() is first);
    assert(reference.compareAndExchange(first, next) is first);
    assert(reference.getAndSet(null) is next);
    assert(reference.compareAndSet(null, first));
    assert(reference.getAndSet(null) is first);
    assert(reference.get() is null);
}
