module flint.conc.random;

import flint.arena : Error;
import flint.conc.sys.random : secureRandom;

@safe:

/// Fill the supplied bytes from the operating system random source.
Error fillSecureRandom(scope ubyte[] output) nothrow @nogc
{
    return secureRandom(output);
}
