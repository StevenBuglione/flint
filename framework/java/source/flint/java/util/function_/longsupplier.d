module flint.java.util.function_.longsupplier;

@safe:

/// Java's `LongSupplier` contract (R9).
interface LongSupplier
{
    /// Evaluate the supplier.
    long getAsLong();

    /// Call the supplier through a D delegate.
    final long delegate() @safe asDelegate()
    {
        return &getAsLong;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static LongSupplier of()(long delegate() @safe callback)
    {
        return new DelegateSupplier!()(callback);
    }
}

private final class DelegateSupplier() : LongSupplier
{
    private long delegate() @safe callback;

    this(long delegate() @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    long getAsLong()
    {
        return callback();
    }
}
