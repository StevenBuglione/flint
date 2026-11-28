// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.zip.ziperror : ZipError;

@safe:

int main(string[] args)
{
    try
        throw new ZipError(args.length > 1 ? args[1] : "invalid zip");
    catch (ZipError error)
        return cast(int)(error.msg.length & 127);
}
