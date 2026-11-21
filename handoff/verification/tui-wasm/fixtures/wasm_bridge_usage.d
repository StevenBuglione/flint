module wasm_bridge_usage;
import flint.wasm_bridge : CommandBuffer, NodeHandle;
import flint.arena : Status;
unittest {
    ubyte[256] memory;
    auto buffer = CommandBuffer.fromStorage(memory[], 7);
    assert(buffer.ok());
    immutable ubyte[] text = [104, 105];
    assert(buffer.value.setText(NodeHandle(0, 1), text).code == Status.ok);
    assert(buffer.value.usedBytes() > 32);
}
