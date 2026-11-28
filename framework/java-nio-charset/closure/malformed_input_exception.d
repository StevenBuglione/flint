// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module malformed_input_exception_probe;

import flint.java.nio.charset.malformedinputexception : MalformedInputException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new MalformedInputException(cast(int) args.length);
        return 0;
    }
    catch (MalformedInputException exception)
    {
        return exception.getInputLength();
    }
}
