// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module proxy_probe;

import flint.java.net.proxy : Proxy;

@safe:

// The address type, named through the proxy so the probe imports only the proxy leaf.
private alias SocketAddress = typeof(Proxy.init.address());

private final class Endpoint : SocketAddress
{
}

int main(string[] args)
{
    SocketAddress endpoint = args.length > 1 ? new Endpoint : null;
    try
    {
        auto proxy = new Proxy(args.length > 2 ? Proxy.Type.SOCKS : Proxy.Type.HTTP, endpoint);
        return proxy.equals(proxy) || proxy.hashCode() == 0 || proxy.toString().length + proxy.type() == 0 ? 1 : 0;
    }
    catch (Exception e)
    {
        return cast(int) e.msg.length & 1;
    }
}
