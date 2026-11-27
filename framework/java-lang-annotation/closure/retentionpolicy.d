module app;

import flint.java.lang.annotation.retentionpolicy : RetentionPolicy;

@safe:

int main(string[] args)
{
    const value = cast(RetentionPolicy)(args.length % 3);
    return (cast(int) value + cast(int) RetentionPolicy.RUNTIME) & 127;
}
