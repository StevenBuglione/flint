// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module closeable_probe;

import flint.java.io.closeable : Closeable;

@safe:

private final class Resource : Closeable
{
    bool open = true;

    override void close()
    {
        open = false;
    }
}

int main(string[] args)
{
    auto resource = new Resource;
    Closeable handle = resource;
    if (args.length > 1)
        handle.close();
    return resource.open ? 1 : 0;
}
