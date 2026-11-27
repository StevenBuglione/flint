// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module cancelled_key_exception_probe;

import flint.java.nio.channels.cancelledkeyexception : CancelledKeyException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new CancelledKeyException;
        return 0;
    }
    catch (CancelledKeyException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
