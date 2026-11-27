module app;

import flint.java.util.function_.longconsumer : LongConsumer;

@safe:

int main(string[] args)
{
    long last = 0;
    auto consumer = LongConsumer.of((long value) { last = value; });
    auto accept = consumer.asDelegate();
    accept(cast(long) args.length);
    return cast(int) last & 127;
}
