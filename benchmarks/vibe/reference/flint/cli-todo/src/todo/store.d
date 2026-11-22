/// The to-do list and its JSON file.
module todo.store;

import flint.arena : Status;

@safe:

/// One to-do item.
struct Item
{
    /// Positive id, never reused.
    ulong id;
    /// What to do.
    string text;
    /// low, normal or high.
    string priority;
    /// Whether it is done.
    bool done;
}

/// The whole list, as stored.
struct TodoList
{
    /// The id the next item gets.
    ulong next = 1;
    /// Items by id.
    Item[] items;

    /// Add an item and return its id.
    ulong add(string text, string priority)
    {
        items ~= Item(next, text, priority, false);
        return next++;
    }

    /// The index of the item with `id`, or -1.
    ptrdiff_t find(ulong id) const
    {
        foreach (index, ref item; items)
        {
            if (item.id == id)
                return index;
        }
        return -1;
    }
}

/// The priorities, in order.
static immutable string[] priorities = ["low", "normal", "high"];

/// Whether `text` names a priority.
bool validPriority(scope const(char)[] text)
{
    foreach (priority; priorities)
    {
        if (priority == text)
            return true;
    }
    return false;
}

/// Read the list from `path`; an absent file is an empty list.
bool readList(string path, out TodoList list, out string failure)
{
    import std.algorithm.mutation : swap;
    import std.file : FileException, exists, readText;
    import flint.serde.owned : deserialize;

    if (!exists(path))
        return true;
    string text;
    try
        text = readText(path);
    catch (FileException error)
    {
        failure = error.msg;
        return false;
    }
    auto parsed = deserialize!TodoList(text);
    if (!parsed.ok)
    {
        failure = path ~ ": " ~ parsed.error.message;
        return false;
    }
    // Take the parsed list without copying it.
    swap(list, parsed.value);
    return true;
}

/// Write the list to `path` atomically, creating its directory.
bool writeList(string path, const ref TodoList list, out string failure)
{
    import std.file : FileException, mkdirRecurse, rename, write;
    import std.path : dirName;
    import flint.serde.owned : serialize;

    const text = serialize(list);
    if (text.error.code != Status.ok)
    {
        failure = text.error.message;
        return false;
    }
    try
    {
        mkdirRecurse(dirName(path));
        const temporary = path ~ ".tmp";
        write(temporary, text.value ~ "\n");
        rename(temporary, path);
    }
    catch (FileException error)
    {
        failure = error.msg;
        return false;
    }
    return true;
}
