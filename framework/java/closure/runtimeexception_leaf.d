// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang.runtimeexception : IllegalArgumentException, IllegalStateException,
    RuntimeException, javaToString;

@safe:

private int classify(RuntimeException failure)
{
    return failure.getMessage() is null ? 1 : 2;
}

int main(string[] args)
{
    int score;
    try
        throw new RuntimeException(args.length > 1 ? args[1] : null);
    catch (RuntimeException failure)
        score += classify(failure);

    try
    {
        auto state = new IllegalStateException(args.length > 2 ? args[2] : null);
        state.initCause(new RuntimeException("cause"));
        score += javaToString(state).length & 1;
    }
    catch (IllegalStateException)
        score += 4;

    try
        throw new IllegalArgumentException("argument");
    catch (IllegalArgumentException failure)
        score += failure.getMessage().length & 1;

    return score & 127;
}
