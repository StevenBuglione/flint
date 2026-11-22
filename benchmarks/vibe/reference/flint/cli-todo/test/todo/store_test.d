module todo.store_test;

import todo.store : TodoList, validPriority;

@safe:

@("ids start at 1 and are never reused after a removal")
unittest
{
    TodoList list;
    assert(list.add("one", "normal") == 1);
    assert(list.add("two", "high") == 2);
    list.items = list.items[1 .. $];
    assert(list.find(1) == -1 && list.find(2) == 0);
    assert(list.add("three", "low") == 3);
}

@("only low, normal and high are priorities")
unittest
{
    assert(validPriority("low") && validPriority("normal") && validPriority("high"));
    assert(!validPriority("urgent") && !validPriority(""));
}
