module app;

import flint.java.util : HashMap;

@safe:

private int hashMap(string arg)
{
    auto map = new HashMap!(string, int)();
    map.put(arg, cast(int) arg.length);
    return map.get(arg);
}

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(hashMap(arg)) & 127;
}
