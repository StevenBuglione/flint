// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module overlapping_file_lock_exception_probe;

import flint.java.nio.channels.overlappingfilelockexception : OverlappingFileLockException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new OverlappingFileLockException;
        return 0;
    }
    catch (OverlappingFileLockException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
