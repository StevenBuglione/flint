module app;

import flint.java.util.function_.intconsumer : IntConsumer;

@safe:

int main(string[] args)
{
    int last;
    auto consumer = IntConsumer.of((int value) { last = value; });
    auto accept = consumer.asDelegate();
    accept(cast(int) args.length);
    return last & 127;
}
