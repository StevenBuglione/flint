// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.malformedurlexception_test;

import flint.java.io : IOException;
import flint.java.net.malformedurlexception : MalformedURLException;

@safe:

@("MalformedURLException is a checked IOException with an optional detail message")
unittest
{
    auto bare = new MalformedURLException();
    IOException asIo = bare;
    assert(asIo !is null);
    assert(bare.getMessage() is null);

    auto detailed = new MalformedURLException("unknown protocol: gopher");
    assert(detailed.getMessage() == "unknown protocol: gopher");
}
