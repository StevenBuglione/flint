// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.zip.zipexception : ZipException;

@safe:

int main(string[] args)
{
    try
        throw new ZipException(args.length > 1 ? args[1] : "invalid zip entry");
    catch (ZipException error)
        return cast(int)(error.msg.length & 127);
}
