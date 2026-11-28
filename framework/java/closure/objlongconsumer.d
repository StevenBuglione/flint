module app;

import flint.java.util.function_.objlongconsumer : ObjLongConsumer;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    long total;
    auto add = ObjLongConsumer!string.of((string text, long number) { total += number + text.length; });
    auto accept = add.asDelegate();
    add.accept("ab", value);
    accept("xyz", 4);
    return cast(int) total & 127;
}
