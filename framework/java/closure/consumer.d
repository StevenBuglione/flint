module app;

import flint.java.util.function_.consumer : Consumer;

@safe:

int main(string[] args)
{
    int result;
    auto consumer = Consumer!int.of((int value) { result = value; });
    auto accept = consumer.asDelegate();
    accept(cast(int) args.length);
    return result & 127;
}
