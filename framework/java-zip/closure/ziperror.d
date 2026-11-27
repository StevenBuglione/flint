// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module ziperror_probe;

import flint.java.util.zip.ziperror : ZipError;

@safe:

int main(string[] args)
{
    const message = args.length > 1 ? args[1] : "invalid zip";
    try
        throw new ZipError(message);
    catch (ZipError error)
        return cast(int) error.msg.length & 127;
}
