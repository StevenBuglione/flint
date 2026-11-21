module wasm_lifetime_usage;
import core.lifetime : move;
import flint.wasm_bridge : CommandBuffer, NodeHandle;
import flint.ui_signals : SignalGraph, SignalSlot, ObserverSlot;
void usage() @safe nothrow @nogc {
    ubyte[256] memory;
    auto created = CommandBuffer.fromStorage(memory[]);
    scope CommandBuffer buffer = move(created.value);
    SignalSlot[8] signals;
    ObserverSlot[8] observers;
    uint[8] queue;
    auto result = SignalGraph.fromStorage(signals[], observers[], queue[]);
    scope SignalGraph graph = move(result.value);
    auto id = graph.create(4);
    auto error = graph.bindText(id.value, NodeHandle(0, 1));
    error = graph.set(id.value, 5);
    error = graph.flush(buffer);
    error = buffer.visit((scope const(ubyte)[] bytes) @safe nothrow @nogc { assert(bytes.length >= 32); });
}
