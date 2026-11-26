module flint.java.util.function_.intsupplier;

@safe:

/// Java's `IntSupplier` contract (R9).
interface IntSupplier
{
    /// Evaluate the supplier.
    int getAsInt();

    /// Call the supplier through a D delegate.
    final int delegate() @safe asDelegate()
    {
        return &getAsInt;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static IntSupplier of()(int delegate() @safe callback)
    {
        return new DelegateSupplier!()(callback);
    }
}

private final class DelegateSupplier() : IntSupplier
{
    private int delegate() @safe callback;

    this(int delegate() @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    int getAsInt()
    {
        return callback();
    }
}
