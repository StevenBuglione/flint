// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module protocol_family_probe;

import flint.java.net.protocolfamily : ProtocolFamily;

@safe:

private final class FixedFamily : ProtocolFamily
{
    private string value;

    this(string value) pure nothrow @nogc
    {
        this.value = value;
    }

    override string name()
    {
        return value;
    }
}

int main(string[] args)
{
    ProtocolFamily family = new FixedFamily(args.length > 1 ? args[1] : "INET");
    return family.name().length > 0 ? 0 : 1;
}
