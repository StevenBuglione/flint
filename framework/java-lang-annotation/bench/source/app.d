module app;

import flint.java.classref : ClassRef;
import flint.java.lang.annotation : Documented, ElementType, Inherited, Native, Repeatable,
    Retention, RetentionPolicy, Target;

@safe:

private int observeMarker(T)(T value, int seed) pure nothrow @nogc
{
    return cast(int) value.sizeof + seed;
}

int main(string[] args)
{
    const policy = cast(RetentionPolicy)(args.length % 3);
    const retention = Retention(policy);
    ElementType[2] targets = [cast(ElementType)(args.length % 12), ElementType.RECORD_COMPONENT,];
    const target = Target(targets[]);
    const repeatable = Repeatable(ClassRef(args.length > 1 ? args[1] : null));
    int acc = cast(int) retention.value + cast(int) target.value[0] + cast(int) target.value.length;
    acc += cast(int) repeatable.value.toString().length;
    acc += observeMarker(Documented(), 1);
    acc += observeMarker(Inherited(), 2);
    acc += observeMarker(Native(), 3);
    return acc & 127;
}
