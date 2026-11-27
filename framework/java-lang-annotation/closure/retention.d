module app;

import flint.java.lang.annotation.retention : Retention;

@safe:

int main(string[] args)
{
    alias Policy = typeof(Retention.init.value);
    const attr = Retention(cast(Policy)(args.length % 3));
    return cast(int) attr.value & 127;
}
