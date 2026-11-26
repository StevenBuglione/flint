// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.nio.file.invalidpathexception : InvalidPathException;
import flint.java.nio.file.path : Path;

@safe:

int main(string[] args)
{
    auto input = args.length > 1 ? args[1] : "";
    auto errorIndex = args.length > 2 ? 0 : -1;
    auto failure = new InvalidPathException(input, "invalid path", errorIndex);
    auto parent = Path.of(input, args.length > 3 ? args[3] : "", "leaf").getParent();
    auto names = parent is null ? 0 : parent.getNameCount();
    return cast(int)((failure.getInput().length + failure.getMessage().length + names) & 127);
}
