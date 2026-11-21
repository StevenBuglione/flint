module cli_usage;
import flint.cli : Command, Option, parse;
import flint.arena : Status;
@Command("count", "Count items")
struct Options { @Option("count", 'n', "Item count") int count = 1; }
unittest {
    auto parsed = parse!Options(["--count", "2"]);
    assert(parsed.error.code == Status.ok);
    assert(parsed.options.count == 2);
    assert(parse!Options(["--count", "2147483648"]).error.code == Status.invalidArgument);
}
