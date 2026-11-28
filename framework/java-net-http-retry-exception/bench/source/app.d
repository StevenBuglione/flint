// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.httpretryexception : HttpRetryException;

@safe:

int main(string[] args)
{
    try
    {
        throw new HttpRetryException(args.length > 0 ? args[0] : "bad", 503, args.length > 1 ? args[1] : null);
    }
    catch (HttpRetryException failure)
    {
        return (cast(int) failure.getReason().length + failure.responseCode()) & 127;
    }
}
