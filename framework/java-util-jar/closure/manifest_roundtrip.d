// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.jar : Attributes, Manifest;

@safe:

int main(string[] args)
{
    auto manifest = new Manifest();
    manifest.getMainAttributes().putValue("Manifest-Version", "1.0");
    manifest.getMainAttributes().putValue("Main-Class", args.length > 1 ? args[1] : "demo.App");
    auto entry = new Attributes();
    entry.putValue("Content-Type", "text/plain");
    manifest.getEntries().put("demo/App.class", entry);
    return manifest.getAttributes("demo/App.class").getValue("Content-Type") == "text/plain" ? 0 : 1;
}
