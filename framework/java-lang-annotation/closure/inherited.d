module app;

import flint.java.lang.annotation.inherited : Inherited;

@safe:

@Inherited
private struct Marked
{
    int value;
}

int main(string[] args)
{
    const item = Marked(cast(int) args.length);
    return (item.value + cast(int) Inherited.sizeof) & 127;
}
