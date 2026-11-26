module app;

import flint.java.lang : IllegalStateException, RuntimeException;

@safe:

int main(string[] args)
{
    if (args.length >= 4)
        return bufferException(args.length);

    version (LittleEndian)
        enum nativeName = "LITTLE_ENDIAN";
    else
        enum nativeName = "BIG_ENDIAN";

    const mode = args.length % 3;
    if (mode == 0)
        return cast(int)(nativeName.length);
    string name = mode == 1 ? "BIG_ENDIAN" : "LITTLE_ENDIAN";
    return cast(int)(name.length);
}

private int bufferException(size_t argumentCount)
{
    try
    {
        if (argumentCount >= 6)
            throw new IllegalStateException;
        throw new RuntimeException;
    }
    catch (RuntimeException error)
        return error.getMessage() is null ? 1 : 2;
}
