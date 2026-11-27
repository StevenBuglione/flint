// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module socket_address_probe;

import flint.java.net.socketaddress : SocketAddress;

@safe:

private final class NamedSocketAddress : SocketAddress
{
    int tag;

    this(int tag) pure nothrow @nogc
    {
        super();
        this.tag = tag;
    }
}

int main(string[] args)
{
    SocketAddress addr = new NamedSocketAddress(cast(int) args.length);
    auto named = cast(NamedSocketAddress) addr;
    return named !is null && named.tag > 0 ? 0 : 1;
}
