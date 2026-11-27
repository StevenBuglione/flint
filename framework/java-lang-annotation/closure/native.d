module app;

import flint.java.lang.annotation.native : Native;

@safe:

private struct Marked
{
    @Native
    enum int FLAG = 7;
    int value;
}

int main(string[] args)
{
    const item = Marked(cast(int) args.length);
    return (item.value + Marked.FLAG + cast(int) Native.sizeof) & 127;
}
