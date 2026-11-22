module flint.test.runner_test;

import flint.test : TestOptions, runTests;
import flint.test.runner_fixture : observedRandom;
import std.algorithm.searching : canFind;
import std.conv : to;
import std.file : exists, readText, remove, tempDir;
import std.path : buildPath;
import std.process : thisProcessID;
import std.random : Random, rndGen;

@safe:

@("runner writes an exclusive JUnit report and seeds the thread-local generator")
unittest
{
    const path = buildPath(tempDir, "flint-test-junit-" ~ thisProcessID.to!string ~ ".xml");
    if (exists(path))
        remove(path);
    scope (exit)
        if (exists(path))
            remove(path);

    const before = rndGen.front;
    TestOptions options;
    options.junitPath = path;
    options.seed = 7;
    assert(runTests!(flint.test.runner_fixture)(options) == 0);
    assert(observedRandom == Random(7).front);
    assert(rndGen.front == before, "the runner restores the generator it seeded");

    const report = readText(path);
    assert(report.canFind(`<testsuite name="Flint" tests="2" failures="0" errors="0">`));
    assert(report.canFind(`<property name="seed" value="7"/>`));
    assert(report.canFind(`<testcase classname="flint.test.runner_fixture" name="captures the seeded generator"/>`));
    assert(report.canFind(`name="escapes &lt;markup&gt; &amp; &quot;quotes&quot;"/>`));

    // An existing report is never overwritten; the run reports the failure and returns 3.
    assert(runTests!(flint.test.runner_fixture)(options) == 3);
    assert(readText(path) == report);
}
