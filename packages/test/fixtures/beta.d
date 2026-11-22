module flint_runner_beta;

import flint.test : expect;

@safe:

private int calls;

@("last")
unittest
{
    expect(++calls).toEqual(1);
}
