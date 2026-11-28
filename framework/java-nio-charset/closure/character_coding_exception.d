// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module character_coding_exception_probe;

import flint.java.nio.charset.charactercodingexception : CharacterCodingException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new CharacterCodingException;
        return 0;
    }
    catch (CharacterCodingException exception)
    {
        return exception.getCause() is null ? 1 : 2;
    }
}
