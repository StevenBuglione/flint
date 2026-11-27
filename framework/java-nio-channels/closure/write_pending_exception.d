// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module write_pending_exception_probe;

import flint.java.nio.channels.writependingexception : WritePendingException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new WritePendingException;
        return 0;
    }
    catch (WritePendingException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
