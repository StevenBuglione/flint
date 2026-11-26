module message_type_tests;

import flint.ai.chat.messages : MessageType;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import std.exception : assertThrown;

@safe:

@("message types retain their Java order and exact wire values")
unittest
{
    auto values = MessageType.values();
    assert(values == [MessageType.USER, MessageType.ASSISTANT, MessageType.SYSTEM, MessageType.TOOL]);
    assert(values[0].getValue() == "user");
    assert(values[1].getValue() == "assistant");
    assert(values[2].getValue() == "system");
    assert(values[3].getValue() == "tool");
    foreach (i, value; values)
    {
        assert(value.ordinal() == i);
        assert(value.toString() == value.name());
        assert(MessageType.valueOf(value.name()) == value);
    }
    values[0] = MessageType.TOOL;
    assert(MessageType.values()[0] == MessageType.USER);
    assertThrown!IllegalArgumentException(MessageType.valueOf("user"));
    assertThrown!NullPointerException(MessageType.valueOf(null));
}
