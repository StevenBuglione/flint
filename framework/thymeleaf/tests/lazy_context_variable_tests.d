/// Contract checks for the lazy context variable classes in Thymeleaf 3.1.7.RELEASE.
module flint.thymeleaf.lazy_context_variable_tests;

import flint.engine.aot.any : Any;
import flint.thymeleaf.context : ILazyContextVariable, LazyContextVariable;

@safe:

private final class Probe(T) : LazyContextVariable!T
{
    private T supplied;
    private Exception firstFailure;
    size_t loads;

    this(T supplied, Exception firstFailure = null)
    {
        this.supplied = supplied;
        this.firstFailure = firstFailure;
    }

    protected override T loadValue()
    {
        ++loads;
        if (loads == 1 && firstFailure !is null)
            throw firstFailure;
        return supplied;
    }
}

@("typed loaders share the erased interface and retain reference identity") unittest
{
    Object marker = new Object();
    auto reference = new Probe!Object(marker);
    auto scalar = new Probe!int(42);
    auto fromReference = cast(ILazyContextVariable) cast(Object) reference;
    ILazyContextVariable fromScalar = scalar;

    assert(reference.loads == 0 && scalar.loads == 0);
    foreach (_; 0 .. 2)
    {
        assert(fromReference.getValue().get!Object() is marker);
        assert(fromScalar.getValue().get!int() == 42);
    }
    assert(reference.loads == 1 && scalar.loads == 1);
}

@("a null result is cached after an initial loader exception") unittest
{
    auto error = new Exception("first read fails");
    auto loader = new Probe!Object(null, error);
    ILazyContextVariable variable = loader;
    try
    {
        variable.getValue();
        assert(0, "expected the first load to fail");
    }
    catch (Exception thrown)
    {
        assert(thrown is error);
    }
    assert(loader.loads == 1);
    assert(variable.getValue().isNull() && variable.getValue().typeName().length == 0);
    assert(loader.loads == 2);

    auto erased = new Probe!Any(Any.of("already erased"));
    assert(erased.getValue().get!string() == "already erased");
}

private final class RecursiveProbe : LazyContextVariable!int
{
    private Exception failure;
    private bool inside;

    this(Exception failure = null)
    {
        this.failure = failure;
    }

    protected override int loadValue()
    {
        if (inside)
            return 1;
        inside = true;
        assert(getValue().get!int() == 1);
        if (failure !is null)
            throw failure;
        return 2;
    }
}

@("recursive loaders keep the final successful result or the nested result after failure") unittest
{
    auto successful = new RecursiveProbe();
    assert(successful.getValue().get!int() == 2);
    assert(successful.getValue().get!int() == 2);

    auto error = new Exception("outer load failed");
    auto failing = new RecursiveProbe(error);
    try
    {
        failing.getValue();
        assert(0, "expected the outer load to fail");
    }
    catch (Exception thrown)
    {
        assert(thrown is error);
    }
    assert(failing.getValue().get!int() == 1);
}

@("concurrent readers share one successful load") @system unittest
{
    import core.sync.barrier : Barrier;
    import core.thread : Thread;

    auto marker = new Object();
    auto loader = new Probe!Object(marker);
    ILazyContextVariable variable = loader;
    Thread[8] workers;
    auto start = new Barrier(workers.length);
    foreach (ref worker; workers)
    {
        worker = new Thread({
            start.wait();
            foreach (_; 0 .. 128)
                assert(variable.getValue().get!Object() is marker);
        });
        worker.start();
    }
    foreach (worker; workers)
        worker.join();
    assert(loader.loads == 1);
}
