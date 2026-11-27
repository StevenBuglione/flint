// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module inet_address_resolver_probe;

import flint.java.net.spi.inetaddressresolver : InetAddressResolver;

@safe:

int main(string[] args)
{
    alias LookupPolicy = InetAddressResolver.LookupPolicy;
    auto policy = LookupPolicy.of(cast(int) args.length | LookupPolicy.IPV4);
    return policy.characteristics() == 0 ? 1 : 0;
}
