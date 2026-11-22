module flint.test;

import std.format : format;
import std.traits : isArray, isFloatingPoint, isSomeString;
import flint.test.internal.mocks : MockState, SelectedMethod;

@safe:

package(flint.test) final class AssertionFailure : Exception
{
    this(string message, string file, size_t line)
    {
        super(message, file, line);
    }
}

/// An assertion over a captured value.
struct Expectation(T)
{
    private T actual;

    /// Compare values with D equality and report the caller's source location.
    void toEqual(scope const T expected, string file = __FILE__, size_t line = __LINE__)
    {
        if (!(actual == expected))
            throw new AssertionFailure(mismatch(expected, actual), file, line);
    }

    static if (is(T == bool))
    {
        /// Require a true boolean value.
        void toBeTrue(string file = __FILE__, size_t line = __LINE__)
        {
            toEqual(true, file, line);
        }

        /// Require a false boolean value.
        void toBeFalse(string file = __FILE__, size_t line = __LINE__)
        {
            toEqual(false, file, line);
        }
    }
}

// Format a mismatch with a quoted string, the first differing array element or a NaN note.
private string mismatch(T)(scope const T expected, scope const T actual)
{
    static if (isSomeString!T)
        return format!"expected %(%s%), received %(%s%)"([expected], [actual]);
    else
    {
        string detail = format!"expected %s, received %s"(expected, actual);
        static if (isArray!T)
        {
            size_t index;
            while (index < expected.length && index < actual.length && expected[index] == actual[index])
                ++index;
            if (index < expected.length && index < actual.length)
                detail ~= format!" (first difference at index %s)"(index);
            else
                detail ~= format!" (lengths %s and %s)"(expected.length, actual.length);
        }
        else static if (isFloatingPoint!T)
        {
            if (expected != expected || actual != actual)
                detail ~= " (NaN never compares equal)";
        }
        return detail;
    }
}

/// Capture a value for a fluent assertion.
Expectation!T expect(T)(T actual)
{
    return Expectation!T(actual);
}

/// Per-mock limits and strictness.
struct MockOptions
{
    /// Treat a call with no configured expectation as a test failure.
    bool strict = true;
    /// Maximum number of calls recorded by one mock.
    uint maxCalls = 256;
}

/// Explicitly select an overload from the compiler's overload list.
alias MockMethod(Contract, string name, size_t overload) = SelectedMethod!(Contract, name, overload);

/// An owned test double. Keep the facade alive while using its interface.
struct Mock(Contract)
{
    private MockState!Contract state;

    private this(MockState!Contract state)
    {
        this.state = state;
    }

    this(this) nothrow @nogc
    {
        if (state !is null)
            state.retain();
    }

    ~this() nothrow @nogc
    {
        if (state !is null)
            state.release();
    }

    /// Allocate the bounded call log and instantiate the generated interface.
    static Mock create(MockOptions options = MockOptions.init)
    {
        return Mock(MockState!Contract.create(options.strict, options.maxCalls));
    }

    /// Obtain the concrete test double through its original interface.
    Contract instance()
    {
        return ownedState().implementation;
    }

    /// Configure the next expected call and its typed return value.
    void returns(alias method, T)(T result)
    {
        enum slot = typeof(state).slotOf!method;
        ownedState().configure!slot(result);
    }

    /// Expect one call to a method returning void.
    void expects(alias method)()
    {
        enum slot = typeof(state).slotOf!method;
        ownedState().configureVoid!slot();
    }

    /// Fail if an expectation was missed or the bounded call log was violated.
    void verify()
    {
        const failure = ownedState().verify();
        if (failure.length != 0)
            throw new AssertionFailure(failure, __FILE__, __LINE__);
    }

    /// Begin another expectation sequence on the same instance.
    void reset()
    {
        ownedState().reset();
    }

    private MockState!Contract ownedState()
    {
        if (state is null || !state.onOwner)
            throw new Exception("mock operations require an initialized mock on its owner thread");
        return state;
    }
}

/// Options for one explicit unit test run.
struct TestOptions
{
    /// Select fully qualified names containing this text.
    string filter;
    /// Stop after the first failed test.
    bool failFast = false;
    /// Optional exclusive output path for a JUnit report.
    string junitPath;
    /// Initial seed of the thread-local random generator.
    uint seed = 1;
    /// Allow an explicit filter to select an empty set.
    bool allowEmpty = false;
}

/// Run unit tests in an explicit module list. Compile the caller with -unittest.
int runTests(Modules...)(TestOptions options)
{
    version (unittest)
    {
        import flint.test.internal.runner : collect, execute;

        return execute(collect!Modules(), options.filter, options.failFast, options.junitPath,
                options.seed, options.allowEmpty);
    }
    else
        static assert(false, "runTests requires a -unittest build");
}
