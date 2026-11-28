// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream;
import flint.java.util.jar : Attributes, Manifest;

@safe:

int main(string[] args)
{
    auto manifest = new Manifest();
    manifest.getMainAttributes().putValue("Manifest-Version", "1.0");
    manifest.getMainAttributes().putValue("Main-Class", args.length > 1 ? args[1] : "demo.App");
    manifest.getEntries().put("demo/App.class", new Attributes());

    auto bytes = new ByteArrayOutputStream();
    manifest.write(bytes);
    auto parsed = new Manifest(new ByteArrayInputStream(bytes.toByteArray()));
    return parsed.getMainAttributes().getValue("Manifest-Version") == "1.0" ? 0 : 1;
}
