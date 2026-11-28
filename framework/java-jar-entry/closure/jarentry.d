// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.jar.jarentry : JarEntry;

@safe:

int main(string[] args)
{
    auto entry = new JarEntry(args.length > 1 ? args[1] : "demo/entry");
    auto copy = new JarEntry(entry);
    return cast(int)(copy.getName().length + copy.getRealName().length + (copy.getAttributes() is null ? 0 : 1));
}
