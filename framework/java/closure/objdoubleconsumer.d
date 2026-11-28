module app;

import flint.java.util.function_.objdoubleconsumer : ObjDoubleConsumer;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    double total = 0.0;
    auto add = ObjDoubleConsumer!string.of((string text, double number) {
        total += number + text.length;
    });
    auto accept = add.asDelegate();
    add.accept("ab", value);
    accept("xyz", 4);
    return cast(int) total & 127;
}
