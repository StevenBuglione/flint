// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.zip.dataformatexception : DataFormatException;

@safe:

int main(string[] args)
{
    try
        throw new DataFormatException(args.length > 1 ? args[1] : "invalid data");
    catch (DataFormatException error)
        return cast(int) error.msg.length & 127;
}
