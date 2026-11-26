// SPDX-License-Identifier: Apache-2.0
module tool_call_value_tests;

import flint.ai.chat.messages : AssistantMessage;
import std.typecons : Nullable, nullable;

@safe:

private alias ToolCall = AssistantMessage.ToolCall;

@("legacy tool calls preserve four ordered record components")
unittest
{
    const call = ToolCall(nullable("call_1"), nullable("function"), nullable("getWeather"),
            nullable(`{"city":"Zürich 🏔"}`));
    const equal = ToolCall(call.id(), call.type(), call.name(), call.arguments());

    assert(call.id().get() == "call_1");
    assert(call.type().get() == "function");
    assert(call.name().get() == "getWeather");
    assert(call.arguments().get() == `{"city":"Zürich 🏔"}`);
    assert(call == equal && call.hashCode() == equal.hashCode());
    assert(call.hashCode() == -2_120_272_249);
    assert(call.toString() == `ToolCall[id=call_1, type=function, name=getWeather, arguments={"city":"Zürich 🏔"}]`);
    assert(call != ToolCall(call.type(), call.id(), call.name(), call.arguments()));
    assert(call != ToolCall(call.id(), call.type(), call.arguments(), call.name()));
}

@("legacy tool calls distinguish missing components from present empty strings")
unittest
{
    const missing = Nullable!string.init;
    const wrappedNull = nullable(cast(string) null);
    const empty = nullable("");
    const absent = ToolCall(missing, wrappedNull, missing, wrappedNull);
    const present = ToolCall(empty, empty, empty, empty);

    assert(absent.id().isNull && absent.type().isNull && absent.name().isNull && absent.arguments().isNull);
    assert(absent == ToolCall(wrappedNull, missing, wrappedNull, missing));
    assert(absent != ToolCall(empty, missing, missing, missing));
    assert(absent != ToolCall(missing, empty, missing, missing));
    assert(absent != ToolCall(missing, missing, empty, missing));
    assert(absent != ToolCall(missing, missing, missing, empty));
    assert(absent.hashCode() == 0 && present.hashCode() == 0);
    assert(absent.toString() == "ToolCall[id=null, type=null, name=null, arguments=null]");
    assert(present.toString() == "ToolCall[id=, type=, name=, arguments=]");
}
