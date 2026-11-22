// Misuse: a JSON field of an unsupported type.
// expect: Order\.callback: `void delegate\(\)[^`]*` cannot be read
module serde_field;
import flint.serde : JsonName;
import flint.serde.owned : deserialize;
struct Order { string id; void delegate() callback; }
void use() { const parsed = deserialize!Order(`{}`); }
