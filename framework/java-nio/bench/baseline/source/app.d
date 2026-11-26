module app;

@safe:

int main(string[] args)
{
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
