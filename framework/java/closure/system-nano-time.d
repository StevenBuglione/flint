module app;

import flint.java.lang.system : System;

@safe:

int main(string[] args) nothrow @nogc
{
    long function() @safe nothrow @nogc clock = &System.nanoTime;
    return (cast(int) clock() ^ cast(int) args.length) & 127;
}
