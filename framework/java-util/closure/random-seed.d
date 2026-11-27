module app;

import flint.java.util.random.random : Random;

@safe:

int main(string[] args)
{
    const long seed = args.length > 1 ? cast(long) args[1].length : 0;
    auto random = new Random(seed);
    const first = random.nextInt();
    byte[5] bytes;
    random.nextBytes(bytes[]);
    if (seed == 0 && (first != -1_155_484_576 || bytes[0] != 0x38 || bytes[4] != 0x7A))
        return 1;
    random.setSeed(seed);
    return random.nextInt() == first ? 0 : 2;
}
