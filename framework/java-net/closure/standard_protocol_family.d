// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module standard_protocol_family_probe;

import flint.java.net.standardprotocolfamily : StandardProtocolFamily, name;

@safe:

int main(string[] args)
{
    const idx = args.length % 3;
    const family = idx == 0 ? StandardProtocolFamily.INET : (idx == 1 ? StandardProtocolFamily.INET6
            : StandardProtocolFamily.UNIX);
    return family.name().length > 0 ? 0 : 1;
}
