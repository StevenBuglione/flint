module app;

import flint.java.lang.annotation.elementtype : ElementType;

@safe:

int main(string[] args)
{
    const value = cast(ElementType)(args.length % 12);
    return (cast(int) value + cast(int) ElementType.RECORD_COMPONENT) & 127;
}
