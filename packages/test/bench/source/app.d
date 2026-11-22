module app;

import flint.test : Mock, TestOptions, runTests;
import probe_fixture : One, Sixteen, SixtyFour, expectedInterfaces, expectedSuite, printChecksum, suiteChecksum;
import probe_suites : Suites;

@safe:

private int exercise(Contract)()
{
    auto mock = Mock!Contract.create();
    static foreach (index, name; __traits(allMembers, Contract))
    {
        {
            alias method = __traits(getMember, Contract, name);
            mock.returns!method(cast(int)(index + 1));
        }
    }

    const instance = mock.instance();
    int checksum;
    static foreach (name; __traits(allMembers, Contract))
        checksum += __traits(getMember, instance, name)();
    mock.verify();
    return checksum;
}

int main()
{
    const interfaces = exercise!One() + exercise!Sixteen() + exercise!SixtyFour();
    const result = runTests!Suites(TestOptions.init);
    const tests = suiteChecksum();
    if (result != 0 || interfaces != expectedInterfaces || tests != expectedSuite)
        return 1;
    printChecksum(interfaces + tests);
    return 0;
}
