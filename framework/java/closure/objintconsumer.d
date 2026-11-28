module app;

import flint.java.util.function_.objintconsumer : ObjIntConsumer;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    long total;
    auto add = ObjIntConsumer!string.of((string text, int number) { total += number + text.length; });
    auto accept = add.asDelegate();
    add.accept("ab", value);
    accept("xyz", 4);
    return cast(int) total & 127;
}
