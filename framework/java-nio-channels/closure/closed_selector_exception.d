// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module closed_selector_exception_probe;

import flint.java.nio.channels.closedselectorexception : ClosedSelectorException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new ClosedSelectorException;
        return 0;
    }
    catch (ClosedSelectorException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
