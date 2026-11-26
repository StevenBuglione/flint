module app;

@safe:

int main(string[] args)
{
    auto words = cast(wchar[]) new ushort[4];
    words[1] = cast(wchar) args.length;
    const view = words[1 .. $];
    return (cast(int) view[0] & 127) + cast(int) view.length;
}
