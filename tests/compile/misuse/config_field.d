// Misuse: a configuration field of an unsupported type.
// expect: Settings\.pool \(key `app\.pool`\): `Pool\*` cannot be bound
module config_field;
import flint.config : ConfigOptions, ConfigurationProperties, load;
struct Pool { int size; }
@ConfigurationProperties("app") struct Settings { string name; Pool* pool; }
void use() { ConfigOptions options; const loaded = load!Settings(options); }
