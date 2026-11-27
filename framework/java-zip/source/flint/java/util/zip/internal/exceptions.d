// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.internal.exceptions;

import flint.java.lang : NullPointerException;

@safe:

pragma(inline, false) package(flint.java.util.zip) void throwNullPointerException(string message)
{
    throw new NullPointerException(message);
}
