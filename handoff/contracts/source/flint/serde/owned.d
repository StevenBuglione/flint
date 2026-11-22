/// Native startup/worker adapter; intentionally uses D GC.
module flint.serde.owned;
import flint.arena : Result;
import flint.serde : DecodeOptions;

@safe:
Result!T deserialize(T)(scope const(char)[] input, DecodeOptions options = DecodeOptions.init);
