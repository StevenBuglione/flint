/// Token-level JSON reading for Spring-layer streaming parsers (Jackson's `JsonParser`), which
/// tokenize one value at a time instead of decoding a whole typed document.
module flint.serde.json_read;

@safe:

package(flint) import flint.serde.internal.json_scan : JsonScanner = Scanner,
    JsonTextToken = TextToken, JsonNumberToken = NumberToken, copyJsonText = copyText;

package(flint) import flint.serde.internal.decimal : parseJsonDecimal = parseDecimal;

package(flint) import flint.serde.internal.types : JsonDecodeOptions = DecodeOptions;
