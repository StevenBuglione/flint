/// ProcessSlot across threads: concurrent setIfAbsent calls leave the published object in place.
module slot;

import core.thread : Thread;
import flint.conc.slot : ProcessSlot;

private final class Box
{
    int value;

    this(int value) @safe
    {
        this.value = value;
    }
}

private shared ProcessSlot!Box published;
private shared ProcessSlot!Box raced;

@("ProcessSlot: every thread sees the object published before it started")
unittest
{
    auto first = new Box(1);
    published.set(first);
    Thread[8] threads;
    shared int mismatches;
    foreach (ref thread; threads)
    {
        thread = new Thread(() {
            if (published.setIfAbsent(new Box(2)) !is first || published.get().value != 1)
            {
                import core.atomic : atomicOp;

                atomicOp!"+="(mismatches, 1);
            }
        });
        thread.start();
    }
    foreach (thread; threads)
        thread.join();
    assert(mismatches == 0 && published.get() is first);
}

@("ProcessSlot: of racing setIfAbsent calls exactly one wins and all see it")
unittest
{
    Thread[8] threads;
    Box[8] winners;
    // Each thread gets its own index: a closure over the loop variable would share one.
    static Thread racer(Box* winner, int index)
    {
        return new Thread(() { *winner = raced.setIfAbsent(new Box(index)); });
    }

    foreach (i, ref thread; threads)
    {
        thread = racer(&winners[i], cast(int) i);
        thread.start();
    }
    foreach (thread; threads)
        thread.join();
    foreach (winner; winners)
        assert(winner is raced.get());
}
