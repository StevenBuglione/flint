module buffer_escape;
import core.lifetime : move;
import flint.wasm_bridge : CommandBuffer;
CommandBuffer leak() @safe nothrow @nogc {
    ubyte[64] localMemory;
    auto result = CommandBuffer.fromStorage(localMemory[]);
    return move(result.value);
}
