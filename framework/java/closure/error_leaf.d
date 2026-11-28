// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang.error : AssertionError, Error_;

@safe:

int main(string[] args)
{
    int score;
    try
        throw new Error_(args.length > 1 ? args[1] : null);
    catch (Error_ failure)
        score += (failure.getMessage() is null ? 1 : 2) + (failure.toString().length & 3);

    try
        throw new AssertionError("expected", new Error_("cause"));
    catch (AssertionError failure)
        score += failure.getCause() is null ? 0 : 8;

    return score & 127;
}
