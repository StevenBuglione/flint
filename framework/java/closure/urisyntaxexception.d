// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.urisyntaxexception : URISyntaxException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 0)
            throw new URISyntaxException(args[0], "reason", 1);
    }
    catch (URISyntaxException e)
        return e.getMessage().length > 0 ? 0 : 1;
    return 1;
}
