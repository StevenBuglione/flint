// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module unsupported_encoding_probe;

import flint.java.io.unsupportedencodingexception : UnsupportedEncodingException;

@safe:

int main(string[] args)
{
    try
        throw new UnsupportedEncodingException(args.length > 1 ? args[1] : "unknown");
    catch (UnsupportedEncodingException failure)
        return cast(int) failure.getMessage().length & 127;
}
