/// Public API contract; declarations are not runtime implementations.
module flint.test;

@safe:
struct Expectation(T)
{
    private T actual;
    void toEqual(scope const T expected, string file = __FILE__, size_t line = __LINE__);
    void toBeTrue(string file = __FILE__, size_t line = __LINE__);
    void toBeFalse(string file = __FILE__, size_t line = __LINE__);
}

Expectation!T expect(T)(T actual);
struct MockOptions
{
    bool strict = true;
    uint maxCalls = 256;
}
/// Concrete implementation is generated once per interface at the test boundary.
struct Mock(Contract)
{
    private Contract implementation;
    static Mock create(MockOptions options = MockOptions.init);
    Contract instance();
    void returns(alias method, T)(T result);
    void verify();
}

struct TestOptions
{
    string filter;
    bool failFast = false;
    string junitPath;
    uint seed = 1;
}

int runTests(Modules...)(TestOptions options);
