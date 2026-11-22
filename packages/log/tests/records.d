module flint.log.records_test;

import core.memory : GC;
import flint.arena : Status;
import flint.log : Field, Level, LogContext, LogOptions, Logger;
import std.json : parseJSON;

@("a structured record escapes control and Unicode bytes and copies borrowed message storage")
unittest
{
    char[4096] target;
    size_t length;
    LogOptions options;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        target[0 .. line.length] = line;
        length = line.length;
        return Status.ok;
    };
    auto created = Logger.create(options);
    assert(created.ok, created.error.message);
    scope (exit)
        created.value.close();

    char[8] message = ['h', 'e', 'l', 'l', 'o', '\0', '"', '\n'];
    const fields = [Field("key", "🌍\t"), Field("Authorization", "secret-value")];
    const before = GC.stats.allocatedInCurrentThread;
    const status = created.value.write(Level.info, message[], fields, LogContext(12, 13, 14, 15));
    const allocated = GC.stats.allocatedInCurrentThread - before;
    assert(status == Status.ok && allocated == 0);
    message[] = '?';
    assert(created.value.flush().code == Status.ok);
    const record = parseJSON(target[0 .. length]);
    assert(record["message"].str == "hello\0\"\n");
    assert(record["requestId"].integer == 12);
    assert(record["fields"]["Authorization"].str == "[REDACTED]");
    assert(record["fields"]["key"].str == "🌍\t");
    assert(record["timestamp"].str.length == 24);
}

@("the complete encoded record accepts 4095 and 4096 bytes and rejects 4097")
unittest
{
    size_t length;
    LogOptions options;
    options.ringBytes = 4096;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        length = line.length;
        return Status.ok;
    };
    auto logger = Logger.create(options).value;
    scope (exit)
        logger.close();

    assert(logger.info("") == Status.ok);
    assert(logger.flush().code == Status.ok);
    const envelope = length;
    assert(envelope < 4095);
    char[4096] body;
    body[] = 'x';
    assert(logger.info(body[0 .. 4095 - envelope]) == Status.ok);
    assert(logger.flush().code == Status.ok && length == 4095);
    assert(logger.info(body[0 .. 4096 - envelope]) == Status.ok);
    assert(logger.flush().code == Status.ok && length == 4096);
    assert(logger.info(body[0 .. 4097 - envelope]) == Status.resourceExhausted);
    assert(logger.stats().accepted[Level.info] == 3);
    assert(logger.stats().dropped[Level.info] == 1);
}

@("empty fields are valid, key bytes are validated, and revealing a sensitive key is explicit")
unittest
{
    char[4096] target;
    size_t length;
    LogOptions options;
    options.allowSensitiveKeys = ["api-key"];
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        target[0 .. line.length] = line;
        length = line.length;
        return Status.ok;
    };
    auto logger = Logger.create(options).value;
    scope (exit)
        logger.close();

    const input = [Field("", ""), Field("Api_Key", "visible"), Field("password", "\xC0\xAF")];
    assert(logger.info("", input) == Status.ok);
    assert(logger.flush().code == Status.ok);
    const record = parseJSON(target[0 .. length]);
    assert(record["message"].str == "");
    assert(record["fields"][""].str == "");
    assert(record["fields"]["Api_Key"].str == "visible");
    assert(record["fields"]["password"].str == "[REDACTED]");
    assert(logger.info("", [Field("\xC0\xAF", "invalid")]) == Status.invalidArgument);
    assert(logger.info("\xED\xA0\x80") == Status.invalidArgument);
    assert(logger.info("", [Field("x", "\xF4\x90\x80\x80")]) == Status.invalidArgument);
}

private LogContext currentTestContext() @safe nothrow @nogc
{
    return LogContext(55, 1, 2, 3);
}

@("console output remains one line and explicit context bypasses the convenience provider")
unittest
{
    import flint.log : Format;
    import std.string : indexOf;

    auto output = new char[8192];
    size_t position;
    LogOptions options;
    options.format = Format.console;
    options.currentContext = &currentTestContext;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        output[position .. position + line.length] = line;
        position += line.length;
        return Status.ok;
    };
    auto logger = Logger.create(options).value;
    scope (exit)
        logger.close();

    assert(logger.info("one\n\x1B") == Status.ok);
    assert(logger.write(Level.warn, "explicit", null, LogContext(77)) == Status.ok);
    assert(logger.flush().code == Status.ok);
    const outputText = output[0 .. position];
    assert(indexOf(outputText, "requestId=55") >= 0);
    assert(indexOf(outputText, "requestId=77") >= 0);
    assert(indexOf(outputText, "one\\u000a\\u001b") >= 0);
    size_t lines;
    foreach (value; outputText)
        if (value == '\n')
            ++lines;
    assert(lines == 2);
}

@("mutating message, key and value storage after write leaves the emitted record unchanged")
unittest
{
    char[4096] target;
    size_t length;
    LogOptions options;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        target[0 .. line.length] = line;
        length = line.length;
        return Status.ok;
    };
    auto created = Logger.create(options);
    assert(created.ok, created.error.message);
    scope (exit)
        created.value.close();

    auto message = "original message".dup;
    auto keyStorage = "region".dup;
    auto valueStorage = "eu-west".dup;
    // Field holds strings, so the test aliases mutable buffers to model caller-owned scratch storage.
    auto borrowed = [Field(cast(string) keyStorage, cast(string) valueStorage)];
    assert(created.value.write(Level.warn, message, borrowed, LogContext(9)) == Status.ok);
    message[] = 'm';
    keyStorage[] = 'k';
    valueStorage[] = 'v';
    borrowed[0] = Field("changed", "changed");
    assert(created.value.flush().code == Status.ok);
    const record = parseJSON(target[0 .. length]);
    assert(record["message"].str == "original message");
    assert(record["level"].str == "warn");
    assert(record["fields"].object.length == 1);
    assert(record["fields"]["region"].str == "eu-west");
}
