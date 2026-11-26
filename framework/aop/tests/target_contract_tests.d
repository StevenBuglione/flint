module target_contract_tests;

import flint.aop : RawTargetAccess;
import flint.aop.interceptor : AsyncUncaughtExceptionHandler;
import flint.aop.scope_ : ScopedObject;
import flint.aop.target : PoolingConfig, ThreadLocalTargetSourceStats;
import flint.aop.target.dynamic : Refreshable;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef, MemberKind, MethodDescriptor, TypeKind;

@safe:

static assert(is(ScopedObject : RawTargetAccess));
static assert(is(typeof(ScopedObject.init.getTargetObject()) == Any));
static assert(is(typeof(ScopedObject.init.removeFromScope()) == void));

static assert(is(PoolingConfig == interface));
static assert(is(typeof(PoolingConfig.init.getMaxSize()) == int));
static assert(is(typeof(PoolingConfig.init.getActiveCount()) == int));
static assert(is(typeof(PoolingConfig.init.getIdleCount()) == int));

static assert(is(ThreadLocalTargetSourceStats == interface));
static assert(is(typeof(ThreadLocalTargetSourceStats.init.getInvocationCount()) == int));
static assert(is(typeof(ThreadLocalTargetSourceStats.init.getHitCount()) == int));
static assert(is(typeof(ThreadLocalTargetSourceStats.init.getObjectCount()) == int));

static assert(is(Refreshable == interface));
static assert(is(typeof(Refreshable.init.refresh()) == void));
static assert(is(typeof(Refreshable.init.getRefreshCount()) == long));
static assert(is(typeof(Refreshable.init.getLastRefreshTime()) == long));

private final class RecordingExceptionHandler : AsyncUncaughtExceptionHandler
{
    private const Descriptor targetType;
    Throwable failure;
    bool matchedMethod;
    Any[] arguments;

    this(const Descriptor targetType)
    {
        this.targetType = targetType;
    }

    override void handleUncaughtException(Throwable failure, MemberDescriptorRef method, Any[] arguments...)
    {
        this.failure = failure;
        matchedMethod = method.declaringType() is targetType && method.name() == "send";
        this.arguments = arguments.dup;
    }
}

@("Async exception handlers receive the failing member, original exception and argument values") unittest
{
    auto targetType = new Descriptor("fixtures.AsyncService", TypeKind.class_);
    targetType.methods = [MethodDescriptor("send", "void")];
    auto handler = new RecordingExceptionHandler(targetType);
    AsyncUncaughtExceptionHandler callback = handler;
    auto method = MemberDescriptorRef(targetType, 0, MemberKind.method);
    auto failure = new Exception("failed");
    auto payload = new Object;

    callback.handleUncaughtException(failure, method, Any.of(payload), Any.init, Any.of(4));
    assert(handler.failure is failure);
    assert(handler.matchedMethod);
    assert(handler.arguments.length == 3);
    assert(handler.arguments[0].asObject() is payload);
    assert(handler.arguments[1].isNull);
    assert(handler.arguments[2].get!int() == 4);

    callback.handleUncaughtException(failure, method);
    assert(handler.arguments.length == 0);
}
