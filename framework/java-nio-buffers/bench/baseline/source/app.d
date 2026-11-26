module app;

@safe:

int main(string[] args)
{
    byte[] bytes = new byte[4];
    bytes[1] = cast(byte) args.length;
    const view = bytes[1 .. $];
    return (cast(int) view[0] & 127) + cast(int) view.length;
}
