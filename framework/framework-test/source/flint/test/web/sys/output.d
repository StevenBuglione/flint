module flint.test.web.sys.output;

@safe:

// SAFETY: fwrite reads at most text.length bytes from the same live slice. stdout is the process C stream.
// The call keeps neither the slice nor its pointer.
package(flint.test.web) bool writeStandardOutput(scope const(char)[] text) @trusted nothrow @nogc
{
    import core.stdc.stdio : fwrite, stdout;

    return text.length == 0 || fwrite(text.ptr, 1, text.length, stdout) == text.length;
}
