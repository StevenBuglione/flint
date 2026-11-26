// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module interrupted_io_probe;

import flint.java.io.interruptedioexception : InterruptedIOException;

@safe:

int main(string[] args)
{
    const message = args.length > 1 ? args[1] : "interrupted";
    auto failure = new InterruptedIOException(message);
    failure.bytesTransferred = cast(int) args.length;
    try
        throw failure;
    catch (InterruptedIOException interrupted)
        return (cast(int) interrupted.getMessage().length + interrupted.bytesTransferred) & 127;
}
