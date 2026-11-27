// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module unresolved_address_exception_probe;

import flint.java.nio.channels.unresolvedaddressexception : UnresolvedAddressException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new UnresolvedAddressException;
        return 0;
    }
    catch (UnresolvedAddressException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
