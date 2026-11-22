/// Two unit tests that `runner_test` runs through the Flint runner.
module flint.test.runner_fixture;

import std.random : rndGen;

@safe:

/// The first value `rndGen` produced inside the fixture, captured for the seed check.
uint observedRandom;

@("captures the seeded generator")
unittest
{
    observedRandom = rndGen.front;
}

@("escapes <markup> & \"quotes\"")
unittest
{
}
