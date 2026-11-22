/// todo: a to-do list with subcommands and a configuration file.
module todo.app;

import flint.cli : Arg, Command, Option, Subcommand;
import todo.store : TodoList;

@safe:

/// `todo add <text...> [--priority low|normal|high]`.
struct Add
{
    /// Overrides `default_priority`.
    @Option("priority", 'p', "low, normal or high") string priority;
    /// The words of the item.
    @Arg(0, "Text of the item") string[] text;
}

/// `todo list [--all] [--json]`.
struct List
{
    /// Include done items.
    @Option("all", 'a', "Include done items") bool all;
    /// Print JSON.
    @Option("json", '\0', "Print a JSON array") bool json;
}

/// `todo done <id>` and `todo remove <id>`.
struct Target
{
    /// The item.
    @Arg(0, "Item id") ulong[] id;
}

/// The command line.
@Command("todo", "Keep a to-do list", "1.0.0")
struct Options
{
    /// Add an item.
    @Subcommand("add", "Add an item") Add add;
    /// List items.
    @Subcommand("list", "List open items") List list;
    /// Mark an item done.
    @Subcommand("done", "Mark an item done") Target done;
    /// Delete an item.
    @Subcommand("remove", "Delete an item") Target remove;
}

/// Exit codes.
enum Exit : int
{
    ok = 0,
    notFound = 1,
    usage = 2,
    configuration = 3,
    storage = 4
}

int main(string[] args)
{
    import std.stdio : write, writeln;
    import flint.arena : Status;
    import flint.cli : ParseAction, parse, writeHelp;
    import todo.settings : Settings, loadSettings;

    const parsed = parse!Options(args[1 .. $]);
    if (parsed.error.code != Status.ok)
        return fail(Exit.usage, parsed.error.message);
    if (parsed.action == ParseAction.help)
    {
        writeHelp!Options(parsed.commandName, (scope const(char)[] text) @safe { write(text.idup); });
        return Exit.ok;
    }
    if (parsed.action == ParseAction.version_)
    {
        writeln("todo 1.0.0");
        return Exit.ok;
    }
    Settings settings;
    string failure;
    if (!loadSettings(settings, failure))
        return fail(Exit.configuration, failure);
    switch (parsed.commandName)
    {
    case "todo add":
        return add(settings, parsed.options.add);
    case "todo list":
        return list(settings, parsed.options.list);
    case "todo done":
        return change(settings, parsed.options.done.id, false);
    case "todo remove":
        return change(settings, parsed.options.remove.id, true);
    default:
        return fail(Exit.usage, "a command is required: add, list, done or remove (todo --help)");
    }
}

private int fail(Exit code, scope const(char)[] message)
{
    import flint.term : Stream, writeStream;

    writeStream(Stream.error, "todo: " ~ message ~ "\n");
    return code;
}

private int add(const ref imported!"todo.settings".Settings settings, const ref Add command)
{
    import std.array : join;
    import std.stdio : writeln;
    import todo.store : validPriority;

    if (command.text.length == 0)
        return fail(Exit.usage, "add needs the text of the item");
    const priority = command.priority.length ? command.priority : settings.defaultPriority;
    if (!validPriority(priority))
        return fail(Exit.usage, "--priority must be low, normal or high");
    TodoList items;
    string failure;
    if (!imported!"todo.store".readList(settings.dataFile, items, failure))
        return fail(Exit.storage, failure);
    const id = items.add(command.text.join(" "), priority);
    if (!imported!"todo.store".writeList(settings.dataFile, items, failure))
        return fail(Exit.storage, failure);
    writeln("added ", id);
    return Exit.ok;
}

private int list(const ref imported!"todo.settings".Settings settings, const ref List command)
{
    import std.stdio : writeln;
    import flint.serde.owned : serialize;
    import todo.store : Item;

    TodoList items;
    string failure;
    if (!imported!"todo.store".readList(settings.dataFile, items, failure))
        return fail(Exit.storage, failure);
    Item[] shown;
    foreach (ref item; items.items)
    {
        if (command.all || !item.done)
            shown ~= item;
    }
    if (command.json)
    {
        const text = serialize(shown);
        if (!text.ok)
            return fail(Exit.storage, text.error.message);
        writeln(text.value);
        return Exit.ok;
    }
    foreach (ref item; shown)
        writeln(item.id, item.done ? " [x] " : " [ ] ", item.priority, " ", item.text);
    return Exit.ok;
}

private int change(const ref imported!"todo.settings".Settings settings, scope const ulong[] id, bool remove)
{
    import std.algorithm.mutation : SwapStrategy, removeAt = remove;
    import std.stdio : writeln;

    if (id.length != 1)
        return fail(Exit.usage, id.length ? "expected one id" : "an item id is required");
    TodoList items;
    string failure;
    if (!imported!"todo.store".readList(settings.dataFile, items, failure))
        return fail(Exit.storage, failure);
    const index = items.find(id[0]);
    if (index < 0)
        return fail(Exit.notFound, "no item with id " ~ imported!"std.conv".to!string(id[0]));
    if (remove)
        items.items = items.items.removeAt!(SwapStrategy.stable)(index);
    else
        items.items[index].done = true;
    if (!imported!"todo.store".writeList(settings.dataFile, items, failure))
        return fail(Exit.storage, failure);
    writeln(remove ? "removed " : "done ", id[0]);
    return Exit.ok;
}
