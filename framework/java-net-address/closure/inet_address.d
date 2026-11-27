// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.inetaddress : Inet6Address, InetAddress;

@safe:

int main(string[] args)
{
    ubyte[] v4 = [10, 0, 0, cast(ubyte) args.length];
    ubyte[] v6 = new ubyte[16];
    v6[0] = 0xfe;
    v6[1] = 0x80;
    v6[15] = cast(ubyte) args.length;
    auto a = InetAddress.getByAddress(args.length > 1 ? args[1] : "probe.test", v4);
    auto b = Inet6Address.getByAddress(a.getHostAddress(), v6, cast(int) args.length);
    auto c = InetAddress.getByAddress(b.getAddress());
    auto d = InetAddress.getByName(args.length > 2 ? args[2] : "[fe80::1%2]");
    auto e = InetAddress.getAllByName(args[0].length > 1 ? "10.0.0.1" : "localhost");
    return a.isSiteLocalAddress() && b.isLinkLocalAddress() && b.equals(c) && d.isLinkLocalAddress()
        && e.length == 1 && b.hashCode() == c.hashCode() && a.toString().length + b.toString().length > 0 ? 0 : 1;
}
