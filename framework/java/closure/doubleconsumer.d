module app;

import flint.java.util.function_.doubleconsumer : DoubleConsumer;

@safe:

int main(string[] args)
{
    double last = 0;
    auto consumer = DoubleConsumer.of((double value) { last = value; });
    auto accept = consumer.asDelegate();
    accept(cast(double) args.length);
    return cast(int) last & 127;
}
