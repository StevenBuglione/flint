module app;

import flint.java.lang.character : isWhitespace;

@safe:

int main(string[] args)
{
    const bytes = args.length > 1 ? args[1] : " \t";
    uint codePoint;
    foreach (byteValue; bytes)
        codePoint = (codePoint << 8) | cast(ubyte) byteValue;
    return isWhitespace(cast(dchar) codePoint) ? 0 : 1;
}
