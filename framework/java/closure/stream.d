module app;

import flint.java.util.stream : stream;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(stream([arg, "other"]).filter(s => s.length > 3).toList().size()) & 127;
}
