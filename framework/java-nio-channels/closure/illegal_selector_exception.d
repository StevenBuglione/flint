// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module illegal_selector_exception_probe;

import flint.java.nio.channels.illegalselectorexception : IllegalSelectorException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new IllegalSelectorException;
        return 0;
    }
    catch (IllegalSelectorException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
