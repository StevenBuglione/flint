/// Bounded UTF-8 JSON emission for protocol adapters with dynamic envelopes.
module flint.serde.json_write;

@safe:

package(flint) import flint.serde.internal.writer : JsonWriter = Writer;

package(flint) import flint.serde.internal.decimal : writeJsonDecimal = writeDecimal;
