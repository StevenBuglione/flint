// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.inetsocketaddress : InetSocketAddress;

@safe:

int main(string[] args)
{
    auto address = new InetSocketAddress(args.length > 1 ? args[1] : "10.0.0.1", 8080);
    return cast(int) address.toString().length & 127;
}
