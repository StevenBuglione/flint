// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang.illegalmonitorstateexception : IllegalMonitorStateException;

@safe:

int main(string[] args)
{
    try
        throw new IllegalMonitorStateException(args.length > 1 ? args[1] : null);
    catch (IllegalMonitorStateException failure)
        return (failure.getMessage() is null ? 1 : 2) + (failure.toString().length & 3);
}
