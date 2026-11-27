module app;

import flint.java.util.random.randomgenerator : RandomGenerator;

@safe:

private final class ProbeGenerator : RandomGenerator
{
    private ulong state;

    this(ulong seed) pure nothrow @nogc
    {
        state = seed;
    }

    override long nextLong()
    {
        state += 0x9e3779b97f4a7c15UL;
        return cast(long) state;
    }

    mixin RandomGenerator.Defaults;
}

int main(string[] args)
{
    RandomGenerator gen = new ProbeGenerator(args.length > 1 ? args[1].length : 0);
    const int i = gen.nextInt();
    const float f = gen.nextFloat();
    const double d = gen.nextDouble();
    const bool b = gen.nextBoolean();
    byte[9] buf;
    gen.nextBytes(buf[]);
    if (gen.isDeprecated())
        return 1;
    if (f < 0.0f || f >= 1.0f || d < 0.0 || d >= 1.0)
        return 2;
    return (i == 0 && !b && buf[0] == 0 && buf[8] == 0) ? 3 : 0;
}
