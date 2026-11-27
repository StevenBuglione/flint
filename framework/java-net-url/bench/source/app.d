// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.url : URL;

@safe:

int main(string[] args)
{
    auto url = new URL(args.length > 1 ? args[1] : "http://Example.test:80/a/b?q=1#f");
    return cast(int)(url.getProtocol().length + url.getPath().length + url.toExternalForm().length) & 127;
}
