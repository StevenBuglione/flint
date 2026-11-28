// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.sockettimeoutexception : SocketTimeoutException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 0)
            throw new SocketTimeoutException(args[0]);
    }
    catch (SocketTimeoutException e)
    {
        return e.getMessage().length > 0 ? 0 : 1;
    }
    return 1;
}
