// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module unsupported_address_type_exception_probe;

import flint.java.nio.channels.unsupportedaddresstypeexception : UnsupportedAddressTypeException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new UnsupportedAddressTypeException;
        return 0;
    }
    catch (UnsupportedAddressTypeException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
