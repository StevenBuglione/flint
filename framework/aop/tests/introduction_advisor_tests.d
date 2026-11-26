module introduction_advisor_tests;

import std.exception : assertThrown;

import flint.aop : DynamicIntroductionAdvice, IntroductionAdvisor, IntroductionInfo;
import flint.aop.support : DefaultIntroductionAdvisor;
import flint.aopalliance.aop : Advice;
import flint.core : Ordered;
import flint.engine.aot.descriptor : Descriptor, TypeKind;
import flint.java.lang : IllegalArgumentException;

@safe:

private final class DeclaredIntroductions : Advice, IntroductionInfo
{
    private const(Descriptor)[] interfaces;

    this(const(Descriptor)[] interfaces)
    {
        this.interfaces = interfaces;
    }

    const(Descriptor)[] getInterfaces()
    {
        return interfaces;
    }

    override string toString() const
    {
        return "test introduction";
    }
}

private final class RecordingAdvisor : DefaultIntroductionAdvisor
{
    size_t registrations;

    this(Advice advice, IntroductionInfo declaration)
    {
        super(advice, declaration);
    }

    override void addInterface(const Descriptor interfaceType)
    {
        ++registrations;
        super.addInterface(interfaceType);
    }
}

private final class SelectiveAdvice : DynamicIntroductionAdvice
{
    private const Descriptor supplied;
    const(Descriptor)[] checked;

    this(const Descriptor supplied)
    {
        this.supplied = supplied;
    }

    bool implementsInterface(const Descriptor interfaceType)
    {
        checked ~= interfaceType;
        return interfaceType is supplied;
    }
}

@("Introduction metadata is ordered, unique and returned as an independent snapshot") unittest
{
    auto timestamped = new Descriptor("example.TimeStamped", TypeKind.interface_);
    auto tester = new Descriptor("example.Tester", TypeKind.interface_);
    auto duplicate = new Descriptor(timestamped.name, TypeKind.interface_);
    auto interfaces = [timestamped, tester, duplicate];
    auto advice = new DeclaredIntroductions(interfaces);
    auto advisor = new DefaultIntroductionAdvisor(advice);
    IntroductionAdvisor contract = advisor;

    assert(contract.getAdvice() is advice);
    assert(contract.isPerInstance());
    assert(advisor.getOrder() == Ordered.LOWEST_PRECEDENCE);
    advisor.setOrder(-5);
    assert(advisor.getOrder() == -5);
    auto filter = contract.getClassFilter();
    assert(filter is advisor);
    assert(filter.matches(new Descriptor("example.Target", TypeKind.class_)));

    interfaces[0] = tester;
    const snapshot = contract.getInterfaces();
    assert(snapshot == [timestamped, tester]);
    const anotherSnapshot = contract.getInterfaces();
    assert(anotherSnapshot.ptr !is snapshot.ptr);
    assert(anotherSnapshot == [timestamped, tester]);
    contract.validateInterfaces();
}

@("Introduction advisors validate only the interfaces selected for dynamic advice") unittest
{
    auto timestamped = new Descriptor("example.TimeStamped", TypeKind.interface_);
    auto tester = new Descriptor("example.Tester", TypeKind.interface_);
    auto advice = new SelectiveAdvice(timestamped);
    auto advisor = new DefaultIntroductionAdvisor(advice, timestamped);
    assert(advice.checked.length == 0);
    advisor.validateInterfaces();
    assert(advice.checked == [timestamped]);

    advisor.addInterface(tester);
    assertThrown!IllegalArgumentException(advisor.validateInterfaces());
    assert(advice.checked == [timestamped, timestamped, tester]);
}

@("Introduction advisors reject null advice, empty declarations and non-interface descriptors") unittest
{
    auto regularClass = new Descriptor("example.Target", TypeKind.class_);
    auto timestamped = new Descriptor("example.TimeStamped", TypeKind.interface_);
    auto plain = new class Advice
    {
    };
    auto advisor = new DefaultIntroductionAdvisor(plain);
    assert(advisor.getInterfaces().length == 0);
    assertThrown!IllegalArgumentException(new DefaultIntroductionAdvisor(null));
    assertThrown!IllegalArgumentException(new DefaultIntroductionAdvisor(new DeclaredIntroductions([
    ])));
    assertThrown!IllegalArgumentException(new DefaultIntroductionAdvisor(plain,
            new DeclaredIntroductions([regularClass])));
    assertThrown!IllegalArgumentException(advisor.addInterface(null));
    assertThrown!IllegalArgumentException(advisor.addInterface(regularClass));

    auto explicit = new DefaultIntroductionAdvisor(plain, new DeclaredIntroductions([timestamped]));
    assert(explicit.getInterfaces() == [timestamped]);
    auto duplicated = new DeclaredIntroductions([timestamped, timestamped]);
    auto recording = new RecordingAdvisor(plain, duplicated);
    assert(recording.registrations == 2 && recording.getInterfaces() == [timestamped]);
}

@("Introduction advisor equality is independent of interface order and advisor precedence") unittest
{
    auto timestamped = new Descriptor("example.TimeStamped", TypeKind.interface_);
    auto tester = new Descriptor("example.Tester", TypeKind.interface_);
    auto advice = new DeclaredIntroductions([timestamped, tester]);
    auto first = new DefaultIntroductionAdvisor(advice);
    auto reversedDeclaration = new DeclaredIntroductions([tester, timestamped]);
    auto reversed = new DefaultIntroductionAdvisor(advice, reversedDeclaration);
    reversed.setOrder(29);
    assert(first.equals(reversed) && first == reversed);
    assert(first.hashCode() == reversed.hashCode());
    assert(!first.equals(new DefaultIntroductionAdvisor(advice, new DeclaredIntroductions([tester]))));
    auto otherAdvice = new DeclaredIntroductions([timestamped, tester]);
    assert(!first.equals(new DefaultIntroductionAdvisor(otherAdvice)));
    assert(!first.equals(null) && !first.equals(new Object));

    enum advisorName = "flint.aop.support.DefaultIntroductionAdvisor";
    enum interfaceNames = "[example.TimeStamped, example.Tester]";
    assert(first.toString() == advisorName ~ ": advice [test introduction]; interfaces " ~ interfaceNames);
}
