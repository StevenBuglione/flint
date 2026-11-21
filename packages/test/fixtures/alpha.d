module flint_runner_alpha;

import flint.test : expect;

@safe:

private int calls;

@("A&B <check> \"quoted\"")
unittest
{
    expect(++calls).toEqual(1);
}

@("failure")
unittest
{
    expect("x&y\x01").toEqual("<actual>");
}

@("uncaught exception")
unittest
{
    throw new Exception("broken & interrupted");
}
