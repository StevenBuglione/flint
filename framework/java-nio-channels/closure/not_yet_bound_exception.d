// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module not_yet_bound_exception_probe;

import flint.java.nio.channels.notyetboundexception : NotYetBoundException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NotYetBoundException;
        return 0;
    }
    catch (NotYetBoundException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
