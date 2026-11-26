module app;

import flint.java.util.function_.consumer : Consumer;

@safe:

int main(string[] args)
{
    int result;
    auto first = Consumer!int.of((int value) { result = value; });
    auto second = Consumer!int.of((int value) { result += value; });
    first.andThen(second).accept(cast(int) args.length);
    return result & 127;
}
