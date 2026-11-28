module app;

import flint.java.util.function_.todoublebifunction : ToDoubleBiFunction;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto mean = ToDoubleBiFunction!(int, int).of((int left, int right) => (left + right) * 0.5);
    auto apply = mean.asDelegate();
    return (cast(int) apply(value, 2)) & 127;
}
