module flint.wasm_bridge;
import flint.arena : Error, Result;

@safe:
@nogc:
nothrow:
enum abiVersion = 1u;
enum Opcode : ushort
{
    createElement = 1,
    setText = 2,
    setAttribute = 3,
    appendChild = 4,
    remove = 5,
    canvas = 6,
    webgpu = 7
}

enum TagName : ushort
{
    div = 1,
    span = 2,
    button = 3,
    input = 4,
    canvas = 5,
    paragraph = 6
}

struct NodeHandle
{
    uint index;
    uint generation;
}

struct EventRecord
{
    uint nodeIndex;
    uint nodeGeneration;
    uint type;
    int value;
}

alias ByteVisitor = void delegate(scope const(ubyte)[]) @safe nothrow @nogc;
struct CommandBuffer
{
@safe:
nothrow:
@nogc:
    private ubyte[] storage_;
    private uint used_ = 32;
    private uint commandCount_;
    private uint sequence_;
    private uint epoch_ = 1;
    private uint activeBorrows_;
    @disable this(this);
    static Result!CommandBuffer fromStorage(return scope ubyte[] callerStorage, uint sessionEpoch = 1);
    Error createElement(NodeHandle node, TagName tag) scope;
    Error setText(NodeHandle node, scope const(ubyte)[] utf8) scope;
    Error setAttribute(NodeHandle node, scope const(ubyte)[] name, scope const(ubyte)[] value) scope;
    Error appendChild(NodeHandle parent, NodeHandle child) scope;
    Error remove(NodeHandle node) scope;
    Error canvas(NodeHandle node, scope const(ubyte)[] commands) scope;
    Error webgpu(NodeHandle node, scope const(ubyte)[] commands) scope;
    Error visit(scope ByteVisitor visitor) scope const;
    uint usedBytes() scope const;
    uint capacityBytes() scope const;
    void clear() scope;
}
