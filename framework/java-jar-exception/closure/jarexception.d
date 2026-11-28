// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.jar.jarexception : JarException;

@safe:

int main(string[] args)
{
    try
        throw new JarException(args.length > 1 ? args[1] : "invalid jar entry");
    catch (JarException error)
        return cast(int)(error.msg.length & 127);
}
