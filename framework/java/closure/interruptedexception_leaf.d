// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang.interruptedexception : InterruptedException;

@safe:

int main(string[] args)
{
    try
        throw new InterruptedException(args.length > 1 ? args[1] : null);
    catch (InterruptedException failure)
        return (failure.getMessage() is null ? 1 : 2) + (failure.getCause() is null ? 0 : 4) + (
                failure.toString().length & 3);
}
