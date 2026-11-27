// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module asynchronous_close_exception_probe;

import flint.java.nio.channels.asynchronouscloseexception : AsynchronousCloseException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new AsynchronousCloseException;
        return 0;
    }
    catch (AsynchronousCloseException exception)
    {
        return exception.getCause() is null ? 1 : 2;
    }
}
