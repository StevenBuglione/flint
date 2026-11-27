// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.proxy : Proxy;

@safe:

int main(string[] args)
{
    try
        return new Proxy(Proxy.Type.HTTP, null).type();
    catch (Exception e)
        return cast(int)(e.msg.length + args.length) & 127;
}
