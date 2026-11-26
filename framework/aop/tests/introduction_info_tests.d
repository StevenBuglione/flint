module introduction_info_tests;

import flint.aop : IntroductionInfo;
import flint.aop.support : IntroductionInfoSupport;
import flint.aopalliance.intercept : MethodInvocation;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef, MemberKind, MethodDescriptor, TypeKind;

@safe:

private final class ConfiguredIntroduction : IntroductionInfoSupport
{
    void publish(Descriptor interfaceType)
    {
        publishedInterfaces.add(interfaceType);
    }

    bool containsIntroducedMethod(MethodInvocation invocation)
    {
        return isMethodOnIntroducedInterface(invocation);
    }
}

private final class TestInvocation : MethodInvocation
{
    private MemberDescriptorRef member;

    this(Descriptor owner)
    {
        member = MemberDescriptorRef(owner, 0, MemberKind.method);
    }

    Any proceed()
    {
        assert(0);
    }

    Any getThis()
    {
        return Any.init;
    }

    MemberDescriptorRef getStaticPart()
    {
        return member;
    }

    Any[] getArguments()
    {
        return null;
    }

    const(MethodDescriptor)* getMethod()
    {
        return member.method();
    }
}

@("Published interfaces keep insertion order and can be suppressed") unittest
{
    auto base = new Descriptor("example.Base", TypeKind.interface_);
    auto child = new Descriptor("example.Child", TypeKind.interface_);
    auto extra = new Descriptor("example.Extra", TypeKind.interface_);
    child.supertypes = [base.name];
    auto introduction = new ConfiguredIntroduction;
    IntroductionInfo info = introduction;

    introduction.publish(child);
    introduction.publish(extra);
    introduction.publish(child);
    const interfaces = info.getInterfaces();
    assert(interfaces.length == 2 && interfaces[0] is child && interfaces[1] is extra);
    assert(introduction.implementsInterface(base));
    assert(introduction.implementsInterface(child));
    assert(!introduction.implementsInterface(new Descriptor("example.Unrelated", TypeKind.interface_)));

    introduction.suppressInterface(base);
    assert(introduction.implementsInterface(base));
    introduction.suppressInterface(child);
    assert(!introduction.implementsInterface(base));
    assert(info.getInterfaces().length == 1 && info.getInterfaces()[0] is extra);
    assert(interfaces.length == 2 && interfaces[0] is child);
}

@("Introduced methods are recognized by the member's declaring interface") unittest
{
    auto parent = new Descriptor("example.Callback", TypeKind.interface_);
    auto child = new Descriptor("example.SpecializedCallback", TypeKind.interface_);
    auto service = new Descriptor("example.Service", TypeKind.class_);
    parent.methods = [MethodDescriptor("handle", "void")];
    service.methods = [MethodDescriptor("handle", "void")];
    child.supertypes = [parent.name];

    auto introduction = new ConfiguredIntroduction;
    introduction.publish(child);
    assert(introduction.containsIntroducedMethod(new TestInvocation(parent)));
    assert(!introduction.containsIntroducedMethod(new TestInvocation(service)));
}
