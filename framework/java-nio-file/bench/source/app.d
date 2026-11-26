// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.nio.file.invalidpathexception : InvalidPathException;

@safe:

int main(string[] args)
{
    auto input = args.length > 1 ? args[1] : "";
    auto errorIndex = args.length > 2 ? 0 : -1;
    auto failure = new InvalidPathException(input, "invalid path", errorIndex);
    return cast(int)((failure.getInput().length + failure.getMessage().length) & 127);
}
