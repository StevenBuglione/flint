module cli_main_usage;
import flint.cli : Command, Option, parse;
@Command("hello", "A real main signature")
struct Options { @Option("name", 'n', "Name") string name = "world"; }
int main(string[] args) @safe {
    auto parsed = parse!Options(args[1 .. $]);
    return parsed.options.name.length == 0 ? 1 : 0;
}
