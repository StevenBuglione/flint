// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.unknownserviceexception : UnknownServiceException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 0)
            throw new UnknownServiceException(args[0]);
    }
    catch (UnknownServiceException e)
    {
        return e.getMessage().length > 0 ? 0 : 1;
    }
    return 1;
}
