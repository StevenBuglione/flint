// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang : IllegalArgumentException;
import flint.java.net.spi.inetaddressresolver : InetAddressResolver;

@safe:

int main(string[] args)
{
    try
        return InetAddressResolver.LookupPolicy.of(cast(int) args.length).characteristics() & 127;
    catch (IllegalArgumentException failure)
        return cast(int) failure.getMessage().length & 127;
}
