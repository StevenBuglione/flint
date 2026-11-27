// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module file_lock_interruption_exception_probe;

import flint.java.nio.channels.filelockinterruptionexception : FileLockInterruptionException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new FileLockInterruptionException;
        return 0;
    }
    catch (FileLockInterruptionException exception)
    {
        return exception.getCause() is null ? 1 : 2;
    }
}
