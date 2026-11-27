// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module interrupted_by_timeout_exception_probe;

import flint.java.nio.channels.interruptedbytimeoutexception : InterruptedByTimeoutException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new InterruptedByTimeoutException;
        return 0;
    }
    catch (InterruptedByTimeoutException exception)
    {
        return exception.getCause() is null ? 1 : 2;
    }
}
