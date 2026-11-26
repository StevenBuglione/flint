module app;

import core.stdc.stdio : fputc, stdout;
import flint.aop : Pointcut;
import flint.aop.support : DynamicMethodMatcherPointcut, Pointcuts;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MethodDescriptor, TypeKind;

@safe:

private final class RenamePointcut : DynamicMethodMatcherPointcut
{
    override bool matches(const(MethodDescriptor)* method, const Descriptor targetClass)
    {
        return method.name == "rename" && targetClass.name == "OwnerService";
    }

    override bool matches(const(MethodDescriptor)* method, const Descriptor targetClass, Any[] args...)
    {
        return args[0].get!string().length != 0;
    }
}

int main(string[] argv)
{
    auto targetClass = new Descriptor("OwnerService", TypeKind.class_);
    auto method = new MethodDescriptor(argv.length > 1 ? argv[1] : "rename", "void");
    auto args = [Any.of(argv.length > 2 ? argv[2] : "Ada")];
    Pointcut pointcut = new RenamePointcut;
    const matched = Pointcuts.matches(pointcut, method, targetClass, args);
    foreach (character; matched ? "matched\n" : "declined\n")
        fputc(character, stdout);
    return 0;
}
