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

@("Java's cause lifecycle: the no-argument and message constructors keep the cause open")
unittest
{
    auto root = new IOException("root cause");
    auto unnamed = new MalformedURLException();
    unnamed.initCause(root);
    assert(unnamed.getCause() is root);

    auto named = new MalformedURLException("detail");
    named.initCause(root);
    assert(named.getCause() is root);
}
