// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.url : URL;

@safe:

int main(string[] args)
{
    const baseSpec = args.length > 1 ? args[1] : "http://Example.test:80/dir/base?old#ref";
    const relSpec = args.length > 2 ? args[2] : "../next?x=1#frag";
    auto base = new URL(baseSpec);
    auto resolved = new URL(base, relSpec);
    auto normalized = new URL("http://example.test/next?x=1#frag");
    auto uri = normalized.toURI();
    return resolved.equals(normalized) && resolved.hashCode() == normalized.hashCode()
        && resolved.toExternalForm().length > 0 && uri.getScheme() == "http" ? 0 : 1;
}
