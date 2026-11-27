// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module coder_malfunction_error_probe;

import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new CoderMalfunctionError(new Exception(args[1]));
        return 0;
    }
    catch (CoderMalfunctionError error)
    {
        return error.getCause() is null ? 1 : cast(int) error.getMessage().length;
    }
}
