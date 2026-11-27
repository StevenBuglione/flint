module app;

import flint.java.lang.annotation.repeatable : Repeatable;

@safe:

int main(string[] args)
{
    alias Ref = typeof(Repeatable.init.value);
    const attr = Repeatable(Ref(args.length > 1 ? args[1] : null));
    return cast(int) attr.value.toString().length & 127;
}
