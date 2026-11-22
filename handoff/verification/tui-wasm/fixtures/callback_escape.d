module callback_escape;
import flint.wasm_bridge : CommandBuffer;
const(ubyte)[] retained;
void leak(ref scope CommandBuffer buffer) @safe nothrow @nogc {
    auto error = buffer.visit((scope const(ubyte)[] bytes) @safe nothrow @nogc { retained = bytes; });
}
