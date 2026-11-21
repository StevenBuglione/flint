module wasi_usage;
import flint.wasi : Plugin, PluginOptions, Engine, GuestAbi;
import flint.arena : Status;
unittest {
    immutable ubyte[] invalid = [1, 2, 3, 4];
    auto loaded = Plugin.load(invalid);
    assert(loaded.error.code == Status.invalidArgument);
    immutable ubyte[] scalar = [
        0, 97, 115, 109, 1, 0, 0, 0,
        1, 5, 1, 96, 0, 1, 127,
        3, 2, 1, 0,
        7, 10, 1, 6, 97, 110, 115, 119, 101, 114, 0, 0,
        10, 6, 1, 4, 0, 65, 42, 11
    ];
    auto valid = Plugin.load(scalar);
    assert(valid.ok(), "Default Wasmtime provider is required");
    scope (exit) valid.value.close();
    auto answer = valid.value.callI32("answer", null);
    assert(answer.ok() && answer.value == 42);
}
