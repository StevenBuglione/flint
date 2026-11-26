module app;

import flint.java.util.function_.function_ : Function;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(Function!(string, size_t).of(s => s.length).apply(arg)) & 127;
}
