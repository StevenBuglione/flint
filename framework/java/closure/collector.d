module app;

import flint.java.util.stream.collector : Characteristics, Collector;

@safe:

private final class Total
{
    int value;
}

int main(string[] args)
{
    const value = cast(int) args.length;
    auto sum = Collector!(int, Total, int).of(() => new Total, (Total total, int e) {
        total.value += e;
    }, (Total left, Total _) => left, (Total total) => total.value);
    auto total = sum.supplier().get();
    sum.accumulator().accept(total, value);
    if (sum.characteristics().contains(Characteristics.IDENTITY_FINISH))
        return 0;
    return sum.finisher().apply(total) & 127;
}
