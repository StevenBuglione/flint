module app;

@safe:

int main(string[] args)
{
    auto words = new int[4];
    words[1] = cast(int) args.length;
    const view = words[1 .. $];
    return (view[0] & 127) + cast(int) view.length;
}
