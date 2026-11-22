module app;

import probe_fixture : One, Sixteen, SixtyFour, decimal, expectedInterfaces, expectedSuite,
    printChecksum, suiteChecksum;
import probe_suites : Suites;

@safe:

private string overrides(Contract)()
{
    string output;
    static foreach (index, name; __traits(allMembers, Contract))
        output ~= "override int " ~ name ~ "() const @safe nothrow @nogc { return " ~ decimal(index + 1) ~ "; }";
    return output;
}

private class DirectImplementation(Contract) : Contract
{
    mixin(overrides!Contract());
}

private int exercise(Contract)()
{
    const Contract instance = new DirectImplementation!Contract;
    int checksum;
    static foreach (name; __traits(allMembers, Contract))
        checksum += __traits(getMember, instance, name)();
    return checksum;
}

int main()
{
    const interfaces = exercise!One() + exercise!Sixteen() + exercise!SixtyFour();
    static foreach (source; Suites)
        static foreach (test; __traits(getUnitTests, source))
            test();
    const tests = suiteChecksum();
    if (interfaces != expectedInterfaces || tests != expectedSuite)
        return 1;
    printChecksum(interfaces + tests);
    return 0;
}
