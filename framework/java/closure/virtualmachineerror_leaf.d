// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang.virtualmachineerror : InternalError, VirtualMachineError;

@safe:

int main(string[] args)
{
    int score;
    try
        throw new InternalError(args.length > 1 ? args[1] : null);
    catch (VirtualMachineError failure)
        score += (failure.getMessage() is null ? 1 : 2) + (failure.toString().length & 3);

    try
        throw new InternalError("detail", new Exception("cause"));
    catch (InternalError failure)
        score += failure.getCause() is null ? 0 : 8;

    return score & 127;
}
