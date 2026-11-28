// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// In flint.java.net, because InterfaceAddress has only package constructors, as in Java.
module flint.java.net.interfaceaddress_bench;

import flint.java.net.interfaceaddress : InterfaceAddress;

@safe:

int main(string[] args)
{
    auto address = new InterfaceAddress(null, null, cast(short) args.length);
    return cast(int)(address.toString().length + address.getNetworkPrefixLength()) & 127;
}
