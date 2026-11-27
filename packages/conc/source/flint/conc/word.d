/// A process-wide 64-bit word, updated atomically by every thread.
module flint.conc.word;

import core.atomic : atomicExchange, atomicLoad, atomicStore, cas;

@safe:

/**
 * One `long` shared by every thread and fiber, with sequentially consistent (Java volatile) ordering: what a
 * Java `volatile long` field updated through a VarHandle is. Declare it `shared`. Its operations are not
 * templates, so a module that uses it compiles none of `core.atomic`'s instantiations (one `atomicLoad` of a
 * `shared long` costs 77 DMD template instances), as `ProcessSlot` does for references.
 */
struct ProcessWord
{
    private long value;

    /// The current value.
    long get() shared nothrow @nogc
    {
        return atomicLoad(value);
    }

    /// Store `newValue`.
    void set(long newValue) shared nothrow @nogc
    {
        atomicStore(value, newValue);
    }

    /// Replace the value if it equals `expected`; whether it did.
    bool compareAndSet(long expected, long newValue) shared nothrow @nogc
    {
        return cas(&value, expected, newValue);
    }

    /// Store `newValue` and return the previous value.
    long getAndSet(long newValue) shared nothrow @nogc
    {
        return atomicExchange(&value, newValue);
    }
}

@("ProcessWord loads, stores, compares and exchanges one shared long")
unittest
{
    shared ProcessWord word;
    assert(word.get() == 0);
    word.set(5);
    assert(!word.compareAndSet(4, 9) && word.get() == 5);
    assert(word.compareAndSet(5, 9) && word.get() == 9);
    assert(word.getAndSet(-1) == 9 && word.get() == -1);
}
