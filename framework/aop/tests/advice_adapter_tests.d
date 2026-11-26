module advice_adapter_tests;

import std.exception : assertThrown, collectException;

import flint.aop : AfterAdvice, AfterReturningAdvice, BeforeAdvice, MethodBeforeAdvice;
import flint.aop.framework.adapter : AfterReturningAdviceInterceptor, MethodBeforeAdviceInterceptor,
    UnknownAdviceTypeException;
import flint.aopalliance.intercept : MethodInterceptor, MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef, MemberKind, MethodDescriptor, TypeKind;
import flint.java.lang : IllegalArgumentException;

@safe:

private final class TestInvocation : MethodInvocation
{
    private MemberDescriptorRef member;
    private Any[] arguments;
    Any target;
    Any result;
    Exception failure;
    int proceeds;

    this(Any target = Any.init, Any result = Any.init)
    {
        auto owner = new Descriptor("example.Service", TypeKind.class_);
        owner.methods = [MethodDescriptor("serve", "Object")];
        member = MemberDescriptorRef(owner, 0, MemberKind.method);
        arguments = [Any.of(1)];
        this.target = target;
        this.result = result;
    }

    Any proceed()
    {
        ++proceeds;
        if (failure !is null)
            throw failure;
        return result;
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

    const(MethodDescriptor)* getMethod()
    {
        return member.method();
    }
}

private final class RecordingAdvice : MethodBeforeAdvice, AfterReturningAdvice
{
    private TestInvocation call;
    int beforeCalls;
    int afterCalls;
    Exception failure;

    this(TestInvocation call)
    {
        this.call = call;
    }

    void before(const(MethodDescriptor)* method, Any[] arguments, Object target)
    {
        ++beforeCalls;
        assert(call.proceeds == 0);
        checkInvocation(method, arguments, target);
        arguments[0] = Any.of(2);
        if (failure !is null)
            throw failure;
    }

    void afterReturning(Any result, const(MethodDescriptor)* method, Any[] arguments, Object target)
    {
        ++afterCalls;
        assert(call.proceeds == 1);
        assert(result == call.result);
        checkInvocation(method, arguments, target);
        if (failure !is null)
            throw failure;
    }

    private void checkInvocation(const(MethodDescriptor)* method, Any[] arguments, Object target)
    {
        assert(method is call.getMethod());
        assert(arguments.ptr is call.getArguments().ptr);
        assert(target is call.target.asObject());
    }
}

@("Before advice runs before proceed with the same method, argument array and target") unittest
{
    auto result = new Object;
    auto call = new TestInvocation(Any.of(new Object), Any.of(result));
    auto advice = new RecordingAdvice(call);
    auto wrapper = new MethodBeforeAdviceInterceptor(advice);
    const BeforeAdvice marker = wrapper;
    assert(marker !is null);

    MethodInterceptor interceptor = wrapper;
    assert(interceptor.invoke(call).asObject() is result);
    assert(advice.beforeCalls == 1 && call.proceeds == 1);
    assert(call.getArguments()[0].get!int() == 2);
}

@("A failure in before advice aborts the invocation") unittest
{
    auto call = new TestInvocation;
    auto advice = new RecordingAdvice(call);
    advice.failure = new Exception("before advice failed");
    auto interceptor = new MethodBeforeAdviceInterceptor(advice);

    assert(collectException(interceptor.invoke(call)) is advice.failure);
    assert(advice.beforeCalls == 1 && call.proceeds == 0);
}

@("After-returning advice follows proceed and preserves the returned object") unittest
{
    auto result = new Object;
    auto call = new TestInvocation(Any.of(new Object), Any.of(result));
    auto advice = new RecordingAdvice(call);
    auto wrapper = new AfterReturningAdviceInterceptor(advice);
    const AfterAdvice marker = wrapper;
    assert(marker !is null);

    MethodInterceptor interceptor = wrapper;
    assert(interceptor.invoke(call).asObject() is result);
    assert(advice.afterCalls == 1 && call.proceeds == 1);
}

@("After-returning advice skips a failed call and propagates its own failure") unittest
{
    auto call = new TestInvocation;
    auto advice = new RecordingAdvice(call);
    auto interceptor = new AfterReturningAdviceInterceptor(advice);

    call.failure = new Exception("target failed");
    assert(collectException(interceptor.invoke(call)) is call.failure);
    assert(advice.afterCalls == 0 && call.proceeds == 1);

    call.failure = null;
    call.proceeds = 0;
    advice.failure = new Exception("after advice failed");
    assert(collectException(interceptor.invoke(call)) is advice.failure);
    assert(advice.afterCalls == 1 && call.proceeds == 1);
}

@("Advice interceptor constructors require advice") unittest
{
    assertThrown!IllegalArgumentException(new MethodBeforeAdviceInterceptor(null));
    assertThrown!IllegalArgumentException(new AfterReturningAdviceInterceptor(null));
}

private final class NamedUnsupportedAdvice
{
    override string toString() const
    {
        return "custom unsupported value";
    }
}

@("Unknown advice diagnostics render the supplied value or explicit message") unittest
{
    enum suffix = "] is neither a supported subinterface of [flint.aopalliance.aop.Advice] nor an [flint.aop.Advisor]";
    auto unsupported = new UnknownAdviceTypeException(Any.of(new NamedUnsupportedAdvice));
    assert(unsupported.msg == "Advice object [custom unsupported value" ~ suffix);
    assert((new UnknownAdviceTypeException(Any.of(42))).msg == "Advice object [42" ~ suffix);
    assert((new UnknownAdviceTypeException(Any.init)).msg == "Advice object [null" ~ suffix);
    assert((new UnknownAdviceTypeException("custom message")).msg == "custom message");
}
