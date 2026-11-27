// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.inetsocketaddress : InetSocketAddress;

@safe:

int main(string[] args)
{
    auto host = args.length > 1 ? args[1] : "Probe.TEST";
    auto wildcard = new InetSocketAddress(cast(int) args.length);
    auto bound = new InetSocketAddress(wildcard.getAddress(), 8000 + cast(int) args.length);
    auto a = InetSocketAddress.createUnresolved(host, 80);
    auto b = InetSocketAddress.createUnresolved(args[0], 80);
    auto c = new InetSocketAddress(args.length > 2 ? args[2] : "::1", 443);
    return a.equals(b) || a.hashCode() == b.hashCode() || bound.equals(wildcard) || c.isUnresolved()
        || bound.toString().length + wildcard.getHostString().length + a.toString().length == 0 ? 1 : 0;
}
