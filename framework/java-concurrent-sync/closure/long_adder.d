module long_adder_probe;

import flint.java.util.concurrent.atomic.longadder : LongAdder;

@safe:

int main(string[] args)
{
    auto adder = new LongAdder();
    adder.add(cast(long) args.length);
    adder.increment();
    adder.decrement();
    if (adder.toString().length != 1)
        return 128;
    const total = adder.sumThenReset() + adder.intValue();
    adder.reset();
    return cast(int)(total + adder.sum()) & 127;
}
