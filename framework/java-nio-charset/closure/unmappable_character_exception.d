// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module unmappable_character_exception_probe;

import flint.java.nio.charset.unmappablecharacterexception : UnmappableCharacterException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new UnmappableCharacterException(cast(int) args.length);
        return 0;
    }
    catch (UnmappableCharacterException exception)
    {
        return exception.getInputLength();
    }
}
