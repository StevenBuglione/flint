module app;

import flint.java.util : ArrayList;

@safe:

private int arrayList(string arg)
{
    auto list = new ArrayList!string();
    list.add(arg);
    return list.size();
}

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)(arrayList(arg)) & 127;
}
