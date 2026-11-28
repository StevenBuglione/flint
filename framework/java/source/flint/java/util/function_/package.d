/++
`java.util.function` (rulebook R9). The module is `function_` because `function` is a D keyword (deviation D-15).

Each functional interface stays an interface, and every Flint API that takes one also accepts a D delegate with the
same parameter and result types, so lambdas infer and no template is instantiated per call site. `of` adapts a
delegate to the interface; `asDelegate` goes the other way.
+/
module flint.java.util.function_;

public import flint.java.util.function_.consumer : Consumer;
public import flint.java.util.function_.doublebinaryoperator : DoubleBinaryOperator;
public import flint.java.util.function_.doubleconsumer : DoubleConsumer;
public import flint.java.util.function_.doublefunction : DoubleFunction;
public import flint.java.util.function_.doublepredicate : DoublePredicate;
public import flint.java.util.function_.doubletointfunction : DoubleToIntFunction;
public import flint.java.util.function_.doubletolongfunction : DoubleToLongFunction;
public import flint.java.util.function_.doubleunaryoperator : DoubleUnaryOperator;
public import flint.java.util.function_.function_ : Function;
public import flint.java.util.function_.intbinaryoperator : IntBinaryOperator;
public import flint.java.util.function_.intconsumer : IntConsumer;
public import flint.java.util.function_.intpredicate : IntPredicate;
public import flint.java.util.function_.intsupplier : IntSupplier;
public import flint.java.util.function_.inttodoublefunction : IntToDoubleFunction;
public import flint.java.util.function_.inttolongfunction : IntToLongFunction;
public import flint.java.util.function_.intunaryoperator : IntUnaryOperator;
public import flint.java.util.function_.longbinaryoperator : LongBinaryOperator;
public import flint.java.util.function_.longconsumer : LongConsumer;
public import flint.java.util.function_.longfunction : LongFunction;
public import flint.java.util.function_.longpredicate : LongPredicate;
public import flint.java.util.function_.longsupplier : LongSupplier;
public import flint.java.util.function_.longtodoublefunction : LongToDoubleFunction;
public import flint.java.util.function_.longtointfunction : LongToIntFunction;
public import flint.java.util.function_.longunaryoperator : LongUnaryOperator;
public import flint.java.util.function_.objdoubleconsumer : ObjDoubleConsumer;
public import flint.java.util.function_.objintconsumer : ObjIntConsumer;
public import flint.java.util.function_.objlongconsumer : ObjLongConsumer;
public import flint.java.util.function_.supplier : Supplier;
public import flint.java.util.function_.todoublebifunction : ToDoubleBiFunction;
public import flint.java.util.function_.todoublefunction : ToDoubleFunction;
public import flint.java.util.function_.tointbifunction : ToIntBiFunction;
public import flint.java.util.function_.tolongbifunction : ToLongBiFunction;
public import flint.java.util.function_.unaryoperator : UnaryOperator;

@safe:

/// Java's `BiFunction`: a two-argument function.
interface BiFunction(T, U, R)
{
    /// Apply the function.
    R apply(T t, U u);

    /// The `apply` method as a delegate.
    final R delegate(T, U) @safe asDelegate()
    {
        return &apply;
    }

    /// A `BiFunction` calling `dg`.
    static BiFunction!(T, U, R) of(R delegate(T, U) @safe dg)
    {
        return new DelegateBiFunction!(T, U, R)(dg);
    }
}

/// Java's `BinaryOperator`: a `BiFunction` of two values of a type to that type.
interface BinaryOperator(T) : BiFunction!(T, T, T)
{
}

/// Java's `BiConsumer`: an operation on two arguments with no result.
interface BiConsumer(T, U)
{
    /// Perform the operation.
    void accept(T t, U u);

    /// The `accept` method as a delegate.
    final void delegate(T, U) @safe asDelegate()
    {
        return &accept;
    }

    /// A `BiConsumer` calling `dg`.
    static BiConsumer!(T, U) of(void delegate(T, U) @safe dg)
    {
        return new DelegateBiConsumer!(T, U)(dg);
    }
}

/// Java's `Predicate`: a boolean-valued function of one argument.
interface Predicate(T)
{
    /// Whether `t` matches.
    bool test(T t);

    /// The `test` method as a delegate.
    final bool delegate(T) @safe asDelegate()
    {
        return &test;
    }

    /// Both this and `other`, short-circuiting.
    final Predicate!T and(Predicate!T other)
    {
        auto self = this;
        return of((T t) => self.test(t) && other.test(t));
    }

    /// This or `other`, short-circuiting.
    final Predicate!T or(Predicate!T other)
    {
        auto self = this;
        return of((T t) => self.test(t) || other.test(t));
    }

    /// The logical negation of this predicate.
    final Predicate!T negate()
    {
        auto self = this;
        return of((T t) => !self.test(t));
    }

    /// A `Predicate` calling `dg`.
    static Predicate!T of(bool delegate(T) @safe dg)
    {
        return new DelegatePredicate!(T)(dg);
    }

    /// Java's `Predicate.not(target)`.
    static Predicate!T not(Predicate!T target)
    {
        return target.negate();
    }
}

/// Java's `BiPredicate`: a boolean-valued function of two arguments.
interface BiPredicate(T, U)
{
    /// Whether `t` and `u` match.
    bool test(T t, U u);

    /// A `BiPredicate` calling `dg`.
    static BiPredicate!(T, U) of(bool delegate(T, U) @safe dg)
    {
        return new DelegateBiPredicate!(T, U)(dg);
    }
}

/// Java's `BooleanSupplier`.
interface BooleanSupplier
{
    /// A result.
    bool getAsBoolean();
}

/// Java's `DoubleSupplier`.
interface DoubleSupplier
{
    /// A result.
    double getAsDouble();

    /// A `DoubleSupplier` calling `dg`.
    static DoubleSupplier of(double delegate() @safe dg)
    {
        return new DelegateDoubleSupplier(dg);
    }
}

private final class DelegateDoubleSupplier : DoubleSupplier
{
    private double delegate() @safe dg;

    this(double delegate() @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    double getAsDouble()
    {
        return dg();
    }
}

unittest
{
    double level = 0.25;
    auto supplier = DoubleSupplier.of(() => level);
    level = 0.5;
    assert(supplier.getAsDouble() == 0.5);
}

/// Java's `IntFunction`.
interface IntFunction(R)
{
    /// Apply the function to `value`.
    R apply(int value);
}

/// Java's `ToIntFunction`.
interface ToIntFunction(T)
{
    /// Apply the function to `value`.
    int applyAsInt(T value);
}

/// Java's `ToLongFunction`.
interface ToLongFunction(T)
{
    /// Apply the function to `value`.
    long applyAsLong(T value);
}

private final class DelegateBiFunction(T, U, R) : BiFunction!(T, U, R)
{
    private R delegate(T, U) @safe dg;

    this(R delegate(T, U) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    R apply(T t, U u)
    {
        return dg(t, u);
    }
}

private final class DelegateBiConsumer(T, U) : BiConsumer!(T, U)
{
    private void delegate(T, U) @safe dg;

    this(void delegate(T, U) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    void accept(T t, U u)
    {
        dg(t, u);
    }
}

private final class DelegatePredicate(T) : Predicate!(T)
{
    private bool delegate(T) @safe dg;

    this(bool delegate(T) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    bool test(T t)
    {
        return dg(t);
    }
}

private final class DelegateBiPredicate(T, U) : BiPredicate!(T, U)
{
    private bool delegate(T, U) @safe dg;

    this(bool delegate(T, U) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    bool test(T t, U u)
    {
        return dg(t, u);
    }
}
