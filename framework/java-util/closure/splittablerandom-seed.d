module app;

import flint.java.util.splittablerandom : SplittableRandom;

@safe:

int main(string[] args)
{
    const long seed = args.length > 1 ? cast(long) args[1].length : 0;
    auto random = new SplittableRandom(seed);
    const first = random.nextInt();
    const wide = random.nextLong();
    auto child = random.split();
    byte[9] bytes;
    child.nextBytes(bytes[]);
    if (seed == 0 && (first != 821_115_357 || wide != 7_960_286_522_194_355_700L || bytes[0] != 18 || bytes[8] != 76))
        return 1;
    return 0;
}
