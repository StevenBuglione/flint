module flint.java.util.function_.consumer;

@safe:

/// Java's `Consumer`: an operation on one argument with no result.
interface Consumer(T)
{
    /// Perform the operation on `t`.
    void accept(T t);

    /// The `accept` method as a delegate.
    final void delegate(T) @safe asDelegate()
    {
        return &accept;
    }

    /// First this consumer, then `after`.
    Consumer andThen()(Consumer after)
    {
        auto self = this;
        return new DelegateConsumer!T((T t) { self.accept(t); after.accept(t); });
    }

    /// A `Consumer` calling `dg`.
    static Consumer of()(void delegate(T) @safe dg)
    {
        return new DelegateConsumer!T(dg);
    }
}

private final class DelegateConsumer(T) : Consumer!(T)
{
    private void delegate(T) @safe dg;

    this(void delegate(T) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    void accept(T t)
    {
        dg(t);
    }
}
