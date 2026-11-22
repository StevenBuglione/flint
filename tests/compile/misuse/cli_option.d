// Misuse: a CLI option of an unsupported type.
// expect: tool\.point: unsupported
module cli_option;
import flint.cli : Command, Option, parse;
struct Point { int x; }
@Command("tool", "A tool") struct Options { @Option("point", 'p', "A point") Point point; }
void use(string[] args) { const parsed = parse!Options(args); }
