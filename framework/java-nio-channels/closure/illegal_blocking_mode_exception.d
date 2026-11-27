// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module illegal_blocking_mode_exception_probe;

import flint.java.nio.channels.illegalblockingmodeexception : IllegalBlockingModeException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new IllegalBlockingModeException;
        return 0;
    }
    catch (IllegalBlockingModeException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
