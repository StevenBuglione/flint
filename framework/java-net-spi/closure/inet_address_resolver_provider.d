// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module inet_address_resolver_provider_probe;

import flint.java.net.spi.inetaddressresolverprovider : InetAddressResolverProvider;

@safe:

// The resolver type, named through the provider so the probe imports only the provider leaf.
private alias Resolver = typeof(InetAddressResolverProvider.init.get(null));

private final class BuiltinProvider : InetAddressResolverProvider
{
    override Resolver get(Configuration configuration)
    {
        return configuration.builtinResolver();
    }

    override string name()
    {
        return "builtin";
    }
}

int main(string[] args)
{
    InetAddressResolverProvider provider = new BuiltinProvider;
    return provider.name().length == args.length ? 1 : 0;
}
