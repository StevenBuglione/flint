module flint.term.internal;

import core.time : MonoTime;
import flint.arena : Error, Status;
import flint.term.events : Event, EventKind, KeyCode, KeyEvent, MouseEvent;

@safe:

package(flint.term) enum readBytes = 32 * 1024;
package(flint.term) enum pasteBytes = 1024 * 1024;
package(flint.term) enum escapeNanos = 25_000_000;

private enum postfix = "\x1b[201~";
private enum MutableState : ubyte
{
    ground,
    escape,
    csi,
    ss3,
    discardSequence,
    paste
}

/// One parser step. An event with consumed=false leaves the byte for the next step.
package(flint.term) struct DecodeStep
{
    bool ready;
    Event value;
    bool consumed = true;
}

package(flint.term) long nowNanos() nothrow @nogc
{
    return (MonoTime.currTime - MonoTime.zero).total!"nsecs";
}

package(flint.term) long deadlineAfter(long now, long delay) pure nothrow @nogc
{
    if (delay < 0 || now > long.max - delay)
        return long.max;
    return now + delay;
}

package(flint.term) struct Decoder
{
    private MutableState mode;
    private long escapeUntil = long.max;
    private ubyte[61] sequence;
    private ubyte sequenceLength;
    private uint codepoint;
    private uint minimum;
    private ubyte continuations;
    private bool alternate;
    private ubyte[] pasteStorage;
    private size_t pasted;
    private ubyte partialMarker;
    private bool droppingPaste;
    private ulong utf8Errors;

    long escapeDeadline() const nothrow @nogc
    {
        return mode == MutableState.escape ? escapeUntil : long.max;
    }

    ulong invalidUtf8Count() const nothrow @nogc
    {
        return utf8Errors;
    }

    DecodeStep expire(long now) nothrow @nogc
    {
        if (mode != MutableState.escape || now < escapeUntil)
            return DecodeStep.init;
        mode = MutableState.ground;
        return key(KeyCode.escape);
    }

    DecodeStep feed(ubyte input, long now)
    {
        final switch (mode)
        {
        case MutableState.ground:
            return continuations != 0 ? continueScalar(input) : ground(input, now);
        case MutableState.escape:
            return afterEscape(input, now);
        case MutableState.csi:
        case MutableState.ss3:
            return inSequence(input, now);
        case MutableState.discardSequence:
            if (input == 0x1B)
                startEscape(now);
            else if (isFinal(input))
                mode = MutableState.ground;
            return DecodeStep.init;
        case MutableState.paste:
            return pasteByte(input);
        }
    }

    DecodeStep endOfInput() nothrow @nogc
    {
        immutable previous = mode;
        mode = MutableState.ground;
        if (continuations != 0)
            return malformed();
        if (previous == MutableState.escape)
            return key(KeyCode.escape);
        if (previous == MutableState.paste && !droppingPaste)
            return inputError(EventKind.paste, Status.invalidArgument, "unterminated bracketed paste");
        return event(EventKind.eof);
    }

    private DecodeStep startEscape(long now) nothrow @nogc
    {
        mode = MutableState.escape;
        escapeUntil = deadlineAfter(now, escapeNanos);
        return DecodeStep.init;
    }

    private DecodeStep ground(ubyte input, long now) nothrow @nogc
    {
        if (input == 0x1B)
            return startEscape(now);
        return character(input, false);
    }

    private DecodeStep afterEscape(ubyte input, long now) nothrow @nogc
    {
        if (now >= escapeUntil || input == 0x1B)
        {
            mode = MutableState.ground;
            DecodeStep standalone = key(KeyCode.escape);
            standalone.consumed = false;
            return standalone;
        }
        if (input == '[' || input == 'O')
        {
            mode = input == '[' ? MutableState.csi : MutableState.ss3;
            sequenceLength = 0;
            return DecodeStep.init;
        }
        mode = MutableState.ground;
        return character(input, true);
    }

    private DecodeStep character(ubyte input, bool alt) nothrow @nogc
    {
        if (input < 0x80)
            return asciiKey(input, alt);
        alternate = alt;
        if (input >= 0xC2 && input <= 0xDF)
        {
            continuations = 1;
            minimum = 0x80;
            codepoint = input & 0x1F;
        }
        else if (input >= 0xE0 && input <= 0xEF)
        {
            continuations = 2;
            minimum = 0x800;
            codepoint = input & 0x0F;
        }
        else if (input >= 0xF0 && input <= 0xF4)
        {
            continuations = 3;
            minimum = 0x1_0000;
            codepoint = input & 0x07;
        }
        else
        {
            return malformed();
        }
        return DecodeStep.init;
    }

    private DecodeStep continueScalar(ubyte input) nothrow @nogc
    {
        if ((input & 0xC0) != 0x80)
        {
            auto rejected = malformed();
            rejected.consumed = false;
            return rejected;
        }
        codepoint = (codepoint << 6) | (input & 0x3F);
        if (--continuations != 0)
            return DecodeStep.init;
        if (codepoint < minimum || codepoint > 0x10_FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
            return malformed();
        return key(KeyCode.character, cast(dchar) codepoint, Modifier(0, alternate));
    }

    private DecodeStep malformed() nothrow @nogc
    {
        if (utf8Errors != ulong.max)
            ++utf8Errors;
        continuations = 0;
        auto result = key(KeyCode.character, '\uFFFD', Modifier(0, alternate));
        result.value.error = Error(Status.invalidArgument, "invalid UTF-8 terminal input");
        return result;
    }

    private DecodeStep inSequence(ubyte input, long now)
    {
        if (input == 0x1B)
            return startEscape(now);
        if (isFinal(input))
            return decodeSequence(input);
        if (sequenceLength == sequence.length)
        {
            mode = MutableState.discardSequence;
            return DecodeStep.init;
        }
        sequence[sequenceLength++] = input;
        return DecodeStep.init;
    }

    private DecodeStep decodeSequence(ubyte token)
    {
        immutable current = mode;
        mode = MutableState.ground;
        scope const(ubyte)[] parameters = sequence[0 .. sequenceLength];
        if (current == MutableState.csi && parameters.length != 0 && parameters[0] == '<')
            return sgrMouse(token, parameters[1 .. $]);

        const decoded = parseParameters(parameters);
        if (!decoded.valid)
            return DecodeStep.init;
        if (current == MutableState.csi && token == '~' && decoded.count == 1 && decoded.values[0] == 200)
        {
            mode = MutableState.paste;
            pasted = 0;
            partialMarker = 0;
            droppingPaste = false;
            return DecodeStep.init;
        }
        return sequenceKey(token, decoded, current);
    }

    private DecodeStep pasteByte(ubyte input)
    {
        if (input == postfix[partialMarker])
        {
            if (++partialMarker != postfix.length)
                return DecodeStep.init;
            mode = MutableState.ground;
            if (droppingPaste)
                return DecodeStep.init;
            auto completed = event(EventKind.paste);
            completed.value.paste = (cast(char[]) pasteStorage[0 .. pasted]).idup;
            return completed;
        }

        bool overflow;
        foreach (index; 0 .. partialMarker)
            overflow = appendPaste(postfix[index]) || overflow;
        partialMarker = 0;
        if (input == postfix[0])
            partialMarker = 1;
        else
            overflow = appendPaste(input) || overflow;

        if (overflow)
            return inputError(EventKind.paste, Status.resourceExhausted, "bracketed paste exceeds 1 MiB");
        return DecodeStep.init;
    }

    private bool appendPaste(ubyte input)
    {
        if (droppingPaste)
            return false;
        if (pasted == pasteBytes)
        {
            droppingPaste = true;
            return true;
        }
        if (pasteStorage is null)
            pasteStorage = new ubyte[pasteBytes];
        pasteStorage[pasted++] = input;
        return false;
    }
}

private struct Modifier
{
    bool control;
    bool alt;
    bool shift;
}

private DecodeStep event(EventKind kind) pure nothrow @nogc
{
    Event output;
    output.kind = kind;
    return DecodeStep(true, output);
}

private DecodeStep inputError(EventKind kind, Status status, string message) pure nothrow @nogc
{
    auto result = event(kind);
    result.value.error = Error(status, message);
    return result;
}

private DecodeStep key(KeyCode code, dchar character = 0, Modifier modifiers = Modifier.init) pure nothrow @nogc
{
    auto result = event(EventKind.key);
    result.value.key = KeyEvent(code, character, modifiers.control, modifiers.alt, modifiers.shift);
    return result;
}

private DecodeStep asciiKey(ubyte input, bool alt) pure nothrow @nogc
{
    Modifier modifiers = Modifier(false, alt, false);
    switch (input)
    {
    case 0x03:
        return event(EventKind.interrupt);
    case '\r':
    case '\n':
        return key(KeyCode.enter, 0, modifiers);
    case '\t':
        return key(KeyCode.tab, 0, modifiers);
    case 0x08:
    case 0x7F:
        return key(KeyCode.backspace, 0, modifiers);
    default:
        if (input < 0x20)
        {
            modifiers.control = true;
            const scalar = input >= 1 && input <= 26 ? 'a' + input - 1 : input + '@';
            return key(KeyCode.character, cast(dchar) scalar, modifiers);
        }
        return key(KeyCode.character, cast(dchar) input, modifiers);
    }
}

private bool isFinal(ubyte input) pure nothrow @nogc
{
    return input >= 0x40 && input <= 0x7E;
}

private struct Parameters
{
    uint[3] values;
    uint count;
    bool valid;
}

private Parameters parseParameters(scope const(ubyte)[] bytes) pure nothrow @nogc
{
    Parameters result;
    result.valid = true;
    if (bytes.length == 0)
        return result;

    result.count = 1;
    bool digits;
    foreach (input; bytes)
    {
        if (input == ';')
        {
            if (!digits || result.count == result.values.length)
                return Parameters.init;
            digits = false;
            ++result.count;
            continue;
        }
        if (input < '0' || input > '9')
            return Parameters.init;
        ref uint value = result.values[result.count - 1];
        immutable digit = input - '0';
        if (value > (uint.max - digit) / 10)
            return Parameters.init;
        value = value * 10 + digit;
        digits = true;
    }
    return digits ? result : Parameters.init;
}

private DecodeStep sequenceKey(ubyte token, Parameters parameters, MutableState current) pure nothrow @nogc
{
    if (parameters.count > 2)
        return DecodeStep.init;
    Modifier modifiers;
    if (parameters.count == 2)
    {
        if (parameters.values[1] < 2 || parameters.values[1] > 8)
            return DecodeStep.init;
        immutable bits = parameters.values[1] - 1;
        modifiers = Modifier((bits & 4) != 0, (bits & 2) != 0, (bits & 1) != 0);
    }

    if (current == MutableState.csi && token == '~')
        return numberedKey(parameters, modifiers);
    if (parameters.count > 0 && parameters.values[0] != 1)
        return DecodeStep.init;
    return keyToken(token, current == MutableState.csi && parameters.count == 0, modifiers);
}

private DecodeStep keyToken(ubyte token, bool plainCsi, Modifier modifiers) pure nothrow @nogc
{
    if (token == 'Z' && plainCsi)
        return key(KeyCode.tab, 0, Modifier(false, false, true));
    if (token >= 'P' && token <= 'S')
        return key(KeyCode.functionKey, cast(dchar)(token - 'P' + 1), modifiers);

    KeyCode direction = navigationKey(token);
    return direction == KeyCode.unknown ? DecodeStep.init : key(direction, 0, modifiers);
}

private KeyCode navigationKey(ubyte token) pure nothrow @nogc
{
    switch (token)
    {
    case 'A':
        return KeyCode.up;
    case 'B':
        return KeyCode.down;
    case 'C':
        return KeyCode.right;
    case 'D':
        return KeyCode.left;
    case 'H':
        return KeyCode.home;
    case 'F':
        return KeyCode.end;
    default:
        return KeyCode.unknown;
    }
}

private DecodeStep numberedKey(Parameters parameters, Modifier modifiers) pure nothrow @nogc
{
    if (parameters.count == 0)
        return DecodeStep.init;
    const number = parameters.values[0];
    switch (number)
    {
    case 1, 7:
        return key(KeyCode.home, 0, modifiers);
    case 4, 8:
        return key(KeyCode.end, 0, modifiers);
    case 3:
        return key(KeyCode.delete_, 0, modifiers);
    case 5:
        return key(KeyCode.pageUp, 0, modifiers);
    case 6:
        return key(KeyCode.pageDown, 0, modifiers);
    default:
        if (number < 11 || number > 24)
            return DecodeStep.init;
        enum ubyte[14] functionKeys = [1, 2, 3, 4, 5, 0, 6, 7, 8, 9, 10, 0, 11, 12];
        immutable ordinal = functionKeys[number - 11];
        return ordinal == 0 ? DecodeStep.init : key(KeyCode.functionKey, ordinal, modifiers);
    }
}

private DecodeStep sgrMouse(ubyte token, scope const(ubyte)[] sequence) pure nothrow @nogc
{
    if (token != 'M' && token != 'm')
        return DecodeStep.init;
    const data = parseParameters(sequence);
    if (!data.valid || data.count != 3 || data.values[0] > 255 || data.values[1] == 0 || data.values[2] == 0)
        return DecodeStep.init;
    immutable button = data.values[0] & 3;
    immutable wheel = (data.values[0] & 64) != 0;
    immutable extended = (data.values[0] & 128) != 0;
    auto output = event(EventKind.mouse);
    output.value.mouse = MouseEvent(data.values[1], data.values[2], cast(ubyte)(button + (wheel
            ? 4 : extended ? 8 : 0)), token == 'M' && (wheel || extended || button != 3));
    return output;
}
