// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.interface_address_probe;

import flint.java.net.interfaceaddress : InterfaceAddress;

@safe:

// The address types, named through the interface address so the probe imports only its leaf.
private alias InetAddress = typeof(InterfaceAddress.init.getAddress());
private alias Inet4Address = typeof(InterfaceAddress.init.broadcast);

int main(string[] args)
{
    const ubyte[4] addrBytes = [192, 168, 1, cast(ubyte)(args.length & 0xFF)];
    const ubyte[4] bcastBytes = [192, 168, 1, 255];
    auto addr = InetAddress.getByAddress(addrBytes[]);
    auto bcast = cast(Inet4Address) InetAddress.getByAddress(bcastBytes[]);
    auto ia1 = new InterfaceAddress(addr, bcast, 24);
    auto ia2 = new InterfaceAddress(addr, bcast, 24);
    return ia1.equals(ia2) && ia1.hashCode() == ia2.hashCode() && ia1.getNetworkPrefixLength() == 24
        && ia1.getAddress() is addr && ia1.getBroadcast() is bcast && ia1.toString().length > 0 ? 0 : 1;
}
