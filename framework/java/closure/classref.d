module app;

import flint.java.classref : classOf;

@safe:

private struct ProbeClass
{
}

int main(string[] args)
{
    return cast(int)(classOf!ProbeClass.name.length + args.length) & 127;
}
