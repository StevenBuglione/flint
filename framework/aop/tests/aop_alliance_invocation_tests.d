module aop_alliance_invocation_tests;

import flint.aop : IntroductionInterceptor;
import flint.aop.support : DefaultIntroductionAdvisor;
import flint.aopalliance.intercept : ConstructorInterceptor, ConstructorInvocation, Invocation,
    Joinpoint, MethodInterceptor, MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, Descriptor, MemberDescriptorRef,
    MemberKind, MethodDescriptor, TypeKind;

@safe:

private final class Accumulator
{
    int value;

    this(int value)
    {
        this.value = value;
    }

    int add(int amount)
    {
        value += amount;
        return value;
    }
}

private final class AddInvocation : MethodInvocation
{
    private MemberDescriptorRef member;
    private Accumulator target;
    private Any[] arguments;

    this(MemberDescriptorRef member, Accumulator target, int amount)
    {
        this.member = member;
        this.target = target;
        arguments = [Any.of(amount)];
    }

    Any proceed()
    {
        return Any.of(target.add(arguments[0].get!int()));
    }

    Any getThis()
    {
        return Any.of(target);
    }

    MemberDescriptorRef getStaticPart()
    {
        return member;
    }

    Any[] getArguments()
    {
        return arguments;
    }

    const(MethodDescriptor)* getMethod()
    {
        return member.method();
    }
}

private final class DoubleAmount : MethodInterceptor
{
    Any invoke(MethodInvocation invocation)
    {
        auto arguments = invocation.getArguments();
        arguments[0] = Any.of(arguments[0].get!int() * 2);
        return invocation.proceed();
    }
}

private final class AccumulatorIntroduction : IntroductionInterceptor
{
    private const Descriptor introduced;

    this(const Descriptor introduced)
    {
        this.introduced = introduced;
    }

    bool implementsInterface(const Descriptor type)
    {
        return introduced is type;
    }

    Any invoke(MethodInvocation invocation)
    {
        return invocation.proceed();
    }
}

private final class NewInvocation : ConstructorInvocation
{
    private MemberDescriptorRef member;
    private Any[] arguments;
    private Any target;

    this(MemberDescriptorRef member, int initial)
    {
        this.member = member;
        arguments = [Any.of(initial)];
    }

    Any proceed()
    {
        target = member.constructor().invoke(arguments);
        return target;
    }

    Any getThis()
    {
        return target;
    }

    MemberDescriptorRef getStaticPart()
    {
        return member;
    }

    Any[] getArguments()
    {
        return arguments;
    }

    const(ConstructorDescriptor)* getConstructor()
    {
        return member.constructor();
    }
}

private final class ChangeInitialValue : ConstructorInterceptor
{
    Any construct(ConstructorInvocation invocation)
    {
        invocation.getArguments()[0] = Any.of(42);
        return invocation.proceed();
    }
}

private Any createAccumulator(scope Any[] arguments)
{
    return Any.of(new Accumulator(arguments[0].get!int()));
}

@("Method interception exposes the member and target and rewrites the invocation arguments") unittest
{
    auto descriptor = new Descriptor("example.Accumulator", TypeKind.class_);
    descriptor.methods = [MethodDescriptor("add", "int")];
    auto target = new Accumulator(10);
    auto invocation = new AddInvocation(MemberDescriptorRef(descriptor, 0, MemberKind.method), target, 3);
    Invocation generic = invocation;
    Joinpoint joinpoint = generic;
    assert(joinpoint.getStaticPart().method() is invocation.getMethod());
    assert(invocation.getMethod().name == "add");
    assert(joinpoint.getThis().asObject() is target);

    MethodInterceptor interceptor = new DoubleAmount;
    assert(interceptor.invoke(invocation).get!int() == 16);
    assert(generic.getArguments()[0].get!int() == 6);
    assert(target.value == 16);
}

@("Constructor interception uses the indexed constructor and retains the constructed object identity") unittest
{
    auto descriptor = new Descriptor("example.Accumulator", TypeKind.class_);
    ConstructorDescriptor constructor;
    constructor.invoke = &createAccumulator;
    descriptor.constructors = [constructor];

    auto invocation = new NewInvocation(MemberDescriptorRef(descriptor, 0, MemberKind.constructor), 10);
    Joinpoint joinpoint = invocation;
    assert(joinpoint.getStaticPart().constructor() is invocation.getConstructor());
    assert(joinpoint.getThis().isNull());

    ConstructorInterceptor interceptor = new ChangeInitialValue;
    const result = interceptor.construct(invocation).get!Accumulator();
    assert(result.value == 42);
    assert(joinpoint.getThis().asObject() is result);
}

@("An introduction interceptor provides the introduced interface and handles the call") unittest
{
    auto introduced = new Descriptor("example.Addable", TypeKind.interface_);
    introduced.methods = [MethodDescriptor("add", "int")];
    IntroductionInterceptor introduction = new AccumulatorIntroduction(introduced);
    auto advisor = new DefaultIntroductionAdvisor(introduction, introduced);
    advisor.validateInterfaces();
    assert(advisor.getInterfaces()[0] is introduced);

    auto target = new Accumulator(10);
    auto invocation = new AddInvocation(MemberDescriptorRef(introduced, 0, MemberKind.method), target, 2);
    auto interceptor = cast(MethodInterceptor) advisor.getAdvice();
    assert(interceptor.invoke(invocation).get!int() == 12);
    assert(target.value == 12);
}
