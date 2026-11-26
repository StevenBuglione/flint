module flint.java.util.function_.intbinaryoperator;

@safe:

/// Java's `IntBinaryOperator` contract (R9).
interface IntBinaryOperator
{
    /// Apply the operator to two integers.
    int applyAsInt(int left, int right);

    /// Call the operator through a D delegate.
    final int delegate(int, int) @safe asDelegate()
    {
        return &applyAsInt;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static IntBinaryOperator of()(int delegate(int, int) @safe callback)
    {
        return new DelegateOperator!()(callback);
    }
}

private final class DelegateOperator() : IntBinaryOperator
{
    private int delegate(int, int) @safe callback;

    this(int delegate(int, int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    int applyAsInt(int left, int right)
    {
        return callback(left, right);
    }
}
