module app;

import flint.java.lang.annotation.documented : Documented;

@safe:

@Documented
private struct Marked
{
    int value;
}

int main(string[] args)
{
    const item = Marked(cast(int) args.length);
    return (item.value + cast(int) Documented.sizeof) & 127;
}
