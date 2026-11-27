// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module closed_by_interrupt_exception_probe;

import flint.java.nio.channels.closedbyinterruptexception : ClosedByInterruptException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ClosedByInterruptException;
        return 0;
    }
    catch (ClosedByInterruptException exception)
    {
        return exception.getCause() is null ? 1 : 2;
    }
}
