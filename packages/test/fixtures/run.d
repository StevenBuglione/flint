module flint_runner_main;

import core.runtime : Runtime, UnitTestResult;
import flint.test : TestOptions, runTests;
import alpha = flint_runner_alpha;
import beta = flint_runner_beta;

// The fixture opts into explicit execution before druntime's default scan.
shared static this()
{
    Runtime.extendedModuleUnitTester = &deferToMain;
}

private UnitTestResult deferToMain()
{
    return UnitTestResult.pass;
}

int main(string[] args) @safe
{
    if (args.length != 5)
        return 64;
    auto options = TestOptions(args[1], args[3] == "fast", args[2], 479, args[4] == "allow-empty");
    return runTests!(beta, alpha, alpha)(options);
}
