module flint.ui_signals;
import flint.arena : Error, Result;
import flint.wasm_bridge : CommandBuffer, NodeHandle;

@safe:
@nogc:
nothrow:
struct SignalId
{
    uint index;
    uint generation;
}

struct SignalSlot
{
    int value;
    uint generation;
    uint firstObserver;
    bool live;
}

alias Compute = int function(scope const(int)[]) @safe nothrow @nogc;
struct ComputedSlot
{
    SignalId output;
    uint firstInput;
    uint inputCount;
    Compute compute;
    bool live;
}

struct ObserverSlot
{
    SignalId source;
    NodeHandle destination;
    uint next;
    bool live;
}

struct SignalGraph
{
@safe:
nothrow:
@nogc:
    private SignalSlot[] signals_;
    private ObserverSlot[] observers_;
    private uint[] dirtyQueue_;
    private ComputedSlot[] computed_;
    private SignalId[] edges_;
    private int[64] scratch_;
    private uint dirtyCount_;
    private uint edgeCount_;
    private bool flushing_;
    @disable this(this);
    static Result!SignalGraph fromStorage(return scope SignalSlot[] signals, return scope ObserverSlot[] observers,
            return scope uint[] dirtyQueue, return scope ComputedSlot[] computedStorage = null,
            return scope SignalId[] edgeStorage = null);
    Result!SignalId create(int initial) scope;
    Result!SignalId computed(scope const SignalId[] inputs, Compute compute) scope;
    Result!int read(SignalId id) scope const;
    Error set(SignalId id, int value) scope;
    Error bindText(SignalId id, NodeHandle node) scope;
    Error dispose(SignalId id) scope;
    Error flush(ref scope CommandBuffer output) scope;
}
