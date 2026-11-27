module app;

import flint.java.lang.annotation.target : Target;

@safe:

int main(string[] args)
{
    alias Kind = typeof(Target.init.value[0]);
    Kind[1] items = [cast(Kind)(args.length % 12)];
    const attr = Target(items[]);
    return (cast(int) attr.value[0] + cast(int) attr.value.length) & 127;
}
