module double_adder_probe;

import flint.java.util.concurrent.atomic.doubleadder : DoubleAdder;

@safe:

int main(string[] args)
{
    auto adder = new DoubleAdder();
    adder.add(cast(double) args.length);
    adder.add(0.5);
    if (adder.toString().length != 3)
        return 128;
    const total = adder.sumThenReset() + adder.intValue();
    adder.reset();
    return cast(int)(total + adder.sum()) & 127;
}
