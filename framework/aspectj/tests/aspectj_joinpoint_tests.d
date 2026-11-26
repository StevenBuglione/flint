module aspectj_joinpoint_tests;

import flint.aspectj.lang : JoinPoint, ProceedingJoinPoint, Signature;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, TypeKind;

@safe:

private final class ExecutionSignature : Signature, JoinPoint.EnclosingStaticPart
{
    private const Descriptor owner;

    this(const Descriptor owner)
    {
        this.owner = owner;
    }

    Signature getSignature()
    {
        return this;
    }

    const(Descriptor) getDeclaringType()
    {
        return owner;
    }

    string getDeclaringTypeName()
    {
        return owner.name;
    }

    string getName()
    {
        return "update";
    }

    int getModifiers()
    {
        return 1;
    }

    string getKind()
    {
        return JoinPoint.METHOD_EXECUTION;
    }

    int getId()
    {
        return 4;
    }

    override string toString() const
    {
        return "Account.update";
    }

    string toShortString()
    {
        return "update";
    }

    string toLongString()
    {
        return "public void example.Account.update(int)";
    }
}

private final class Invocation : ProceedingJoinPoint
{
    private JoinPoint.StaticPart metadata;
    private Any proxy;
    private Any target;
    private Any[] arguments;

    this(JoinPoint.StaticPart metadata, Any proxy, Any target, Any[] arguments)
    {
        this.metadata = metadata;
        this.proxy = proxy;
        this.target = target;
        this.arguments = arguments;
    }

    override string toString() const
    {
        return "execution(Account.update)";
    }

    string toShortString()
    {
        return metadata.toShortString();
    }

    string toLongString()
    {
        return metadata.toLongString();
    }

    Any getThis()
    {
        return proxy;
    }

    Any getTarget()
    {
        return target;
    }

    Any[] getArgs()
    {
        return arguments.dup;
    }

    Signature getSignature()
    {
        return metadata.getSignature();
    }

    string getKind()
    {
        return metadata.getKind();
    }

    JoinPoint.StaticPart getStaticPart()
    {
        return metadata;
    }

    Any proceed()
    {
        return proceed(arguments);
    }

    Any proceed(Any[] arguments)
    {
        return arguments[0];
    }
}

@("AspectJ join points retain receiver, target, declaring type and static signature identity") unittest
{
    auto owner = new Descriptor("example.Account", TypeKind.class_);
    auto part = new ExecutionSignature(owner);
    auto proxy = new Object;
    auto target = new Object;

    JoinPoint joinpoint = new Invocation(part, Any.of(proxy), Any.of(target), [Any.of(7)]);
    assert(joinpoint.getThis().asObject() is proxy);
    assert(joinpoint.getTarget().asObject() is target);
    assert(joinpoint.getArgs()[0].get!int() == 7);
    assert(joinpoint.getStaticPart() is cast(JoinPoint.StaticPart) part);
    assert(joinpoint.getStaticPart().getId() == 4);
    assert(joinpoint.getSignature() is joinpoint.getStaticPart().getSignature());
    assert(joinpoint.getSignature().getDeclaringType() is owner);
    assert(joinpoint.getSignature().getDeclaringTypeName() == "example.Account");
    assert(joinpoint.getKind() == "method-execution");
    assert(joinpoint.toShortString() == "update");
}

@("ProceedingJoinPoint accepts original or replacement argument arrays") unittest
{
    auto owner = new Descriptor("example.Account", TypeKind.class_);
    ProceedingJoinPoint joinpoint = new Invocation(new ExecutionSignature(owner), Any.init, Any.init, [
        Any.of(7)
    ]);
    assert(joinpoint.getThis().isNull && joinpoint.getTarget().isNull);
    assert(joinpoint.proceed().get!int() == 7);

    auto replacement = new Object;
    assert(joinpoint.proceed([Any.of(replacement)]).asObject() is replacement);
    assert(joinpoint.getArgs()[0].get!int() == 7);
}
