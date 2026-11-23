module flint.validate.internal.pattern;

import flint.validate.internal.letters : isUnicodeLetter;
import flint.validate.internal.text : decodeScalar;

@safe:

private enum stateLimit = 256;
private enum byteLimit = 16_384;
private enum unbounded = ushort.max;

private enum Op : ubyte
{
    empty,
    accept,
    literal,
    any,
    selection,
    begin,
    end,
    sequence,
    choice,
    repeat
}

// Which non-ASCII code points a selection contains.
private enum Wide : ubyte
{
    none,
    all,
    letters, // \p{L}
    nonLetters, // \P{L}
}

private struct Selection
{
    ulong[2] bits;
    Wide wide;

    void include(uint first, uint last) pure nothrow @nogc
    {
        foreach (cp; first .. last + 1)
            bits[cp >> 6] |= 1UL << (cp & 63);
    }

    void merge(Selection other) pure nothrow @nogc
    {
        bits[0] |= other.bits[0];
        bits[1] |= other.bits[1];
        // Letters with non-letters, or anything with all, is every code point.
        if (wide == Wide.none || other.wide == Wide.all)
            wide = other.wide;
        else if (other.wide != Wide.none && other.wide != wide)
            wide = Wide.all;
    }

    void invert() pure nothrow @nogc
    {
        static immutable Wide[4] inverse = [Wide.all, Wide.none, Wide.nonLetters, Wide.letters];
        bits[0] = ~bits[0];
        bits[1] = ~bits[1];
        wide = inverse[wide];
    }

    bool contains(uint cp) const pure nothrow @nogc
    {
        if (cp < 128)
            return (bits[cp >> 6] & (1UL << (cp & 63))) != 0;
        final switch (wide)
        {
        case Wide.none:
            return false;
        case Wide.all:
            return true;
        case Wide.letters:
            return isUnicodeLetter(cp);
        case Wide.nonLetters:
            return !isUnicodeLetter(cp);
        }
    }
}

private struct Leaf
{
    int character = -1;
    Selection selection;
}

private struct Term
{
    Op op;
    ushort first;
    ushort second;
    ushort minimum;
    ushort maximum;
    Selection selection;
}

// The parser and lowering run only when a Pattern UDA is instantiated.
private struct RegexParser(size_t capacity)
{
    string expression;
    size_t offset;
    // Each source byte adds at most two terms, plus the empty term: 8,193 at the
    // 4,096-byte limit. Sizing per pattern keeps compile-time evaluation small.
    Term[capacity] terms;
    ushort termCount;
    string error;
    // \p{L} and \P{L}: only for run-time patterns (Jakarta `@Pattern`, which follows java.util.regex). The
    // compile-time pattern contract (handoff/specs/tier-1/validate.md) rejects Unicode property escapes.
    bool unicodeProperties;

    int peek() const pure nothrow @nogc
    {
        return offset < expression.length ? expression[offset] : -1;
    }

    bool take(int expected) pure nothrow @nogc
    {
        if (peek() != expected)
            return false;
        ++offset;
        return true;
    }

    ushort add(Term term)
    {
        terms[termCount] = term;
        return termCount++;
    }

    ushort parse(uint depth = 0)
    {
        ushort result = concatenate(depth);
        while (error is null && take('|'))
        {
            immutable branch = concatenate(depth);
            if (result != branch)
                result = add(Term(Op.choice, result, branch));
        }
        return result;
    }

    private ushort concatenate(uint depth)
    {
        ushort result;
        while (error is null && offset < expression.length && peek() != ')' && peek() != '|')
        {
            immutable item = quantify(atom(depth));
            if (item == 0)
                continue;
            result = result == 0 ? item : add(Term(Op.sequence, result, item));
        }
        return result;
    }

    private ushort atom(uint depth)
    {
        enum reserved = "*+?{}]";
        immutable ch = peek();
        ++offset;
        switch (ch)
        {
        case '(':
            return group(depth);
        case '[':
            return add(Term(Op.selection, 0, 0, 0, 0, characterClass()));
        case '\\':
            immutable escaped = escape();
            return escaped.character >= 0 ? add(Term(Op.literal,
                    cast(ushort) escaped.character)) : add(Term(Op.selection, 0, 0, 0, 0, escaped.selection));
        case '.':
            return add(Term(Op.any));
        case '^':
            return add(Term(Op.begin));
        case '$':
            return add(Term(Op.end));
        default:
            foreach (reservedChar; reserved)
            {
                if (ch == reservedChar)
                    return fail("misplaced pattern metacharacter");
            }
            if (ch >= 128)
                return fail("pattern literals must use ASCII");
            return add(Term(Op.literal, cast(ushort) ch));
        }
    }

    private ushort group(uint depth)
    {
        if (depth == 128)
            return fail("pattern grouping depth exceeds 128");
        if (peek() == '?')
            return fail("look-around and extended groups are unsupported");
        immutable part = parse(depth + 1);
        if (error is null && !take(')'))
            return fail("unclosed pattern group");
        return part;
    }

    private ushort quantify(ushort item)
    {
        if (error !is null)
            return item;

        const repetition = readQuantifier(item);
        if (repetition.op == Op.empty)
            return item;
        if (error !is null || repetition.maximum == 0 || item == 0)
            return 0;
        if (terms[item].op == Op.begin || terms[item].op == Op.end)
            return fail("pattern anchors cannot be repeated");
        return add(repetition);
    }

    private Term readQuantifier(ushort item)
    {
        const token = peek();
        switch (token)
        {
        case '?':
        case '*':
        case '+':
            ++offset;
            return Term(Op.repeat, item, 0, token == '+' ? 1 : 0, token == '?' ? 1 : unbounded);
        case '{':
            ++offset;
            const minimum = repetitionCount();
            const maximum = take(',') ? peek() == '}' ? unbounded : repetitionCount() : minimum;
            if (error is null && (!take('}') || maximum < minimum))
                fail("invalid pattern repetition interval");
            return Term(Op.repeat, item, 0, minimum, maximum);
        default:
            return Term.init;
        }
    }

    private ushort repetitionCount()
    {
        if (peek() < '0' || peek() > '9')
            return fail("expected a numeric pattern repetition bound");
        uint count;
        while (peek() >= '0' && peek() <= '9')
        {
            count = count * 10 + cast(uint)(peek() - '0');
            ++offset;
            if (count > stateLimit)
                return fail("pattern repetition exceeds the 256-state limit");
        }
        return cast(ushort) count;
    }

    private Selection characterClass()
    {
        const negated = take('^');
        Selection result;
        if (peek() == ']')
            fail("empty pattern character class");
        while (error is null && peek() >= 0 && peek() != ']')
        {
            const first = classLeaf();
            if (peek() == '-' && offset + 1 < expression.length && expression[offset + 1] != ']')
            {
                ++offset;
                const last = classLeaf();
                if (first.character < 0 || last.character < first.character)
                    fail("invalid pattern character range");
                else
                    result.include(cast(uint) first.character, cast(uint) last.character);
            }
            else if (first.character >= 0)
            {
                result.include(cast(uint) first.character, cast(uint) first.character);
            }
            else
            {
                result.merge(first.selection);
            }
        }
        if (error is null && !take(']'))
            fail("unclosed pattern character class");
        if (negated)
            result.invert();
        return result;
    }

    private Leaf classLeaf()
    {
        if (take('\\'))
            return escape();
        immutable literal = peek();
        if (literal < 0 || literal >= 128)
        {
            fail("pattern character classes require ASCII literals");
            return Leaf.init;
        }
        ++offset;
        return Leaf(literal);
    }

    private Leaf escape()
    {
        const ch = peek();
        if (ch < 0 || ch >= 128)
        {
            fail("invalid pattern escape");
            return Leaf.init;
        }
        ++offset;
        immutable lower = ch | 0x20;
        if (lower == 'd' || lower == 'w' || lower == 's')
            return Leaf(-1, shorthand(ch));
        if (lower == 'p' && unicodeProperties)
            return Leaf(-1, category(ch == 'P'));
        if (ch == 'x')
            return Leaf(hexByte());
        return plainEscape(ch, lower);
    }

    // A control-character mnemonic or an escaped punctuation character.
    private Leaf plainEscape(int ch, int lower)
    {
        enum mnemonic = "nrtfv";
        enum escaped = "\n\r\t\f\v";
        foreach (index, letter; mnemonic)
        {
            if (ch == letter)
                return Leaf(escaped[index]);
        }
        if (ch >= '0' && ch <= '9')
            fail("backreferences and numeric escapes are unsupported");
        else if (lower >= 'a' && lower <= 'z')
            fail("unsupported pattern escape");
        return Leaf(ch);
    }

    // \p{L} and \P{L} (also \pL, \p{IsL} and \p{IsLetter}): java.util.regex's Unicode letter category.
    private Selection category(bool negated)
    {
        size_t start = offset, end = offset + 1;
        if (take('{'))
        {
            start = offset;
            while (peek() >= 0 && peek() != '}')
                ++offset;
            end = offset;
            if (!take('}'))
                fail("unclosed pattern property name");
        }
        else
            ++offset;
        const name = end <= expression.length ? expression[start .. end] : "";
        Selection letters;
        if (name == "L" || name == "IsL" || name == "IsLetter")
        {
            letters.include('A', 'Z');
            letters.include('a', 'z');
            letters.wide = Wide.letters;
        }
        else if (error is null)
            fail("unsupported pattern property: only \\p{L} is supported");
        if (negated)
            letters.invert();
        return letters;
    }

    private int hexByte()
    {
        immutable first = hexValue(peek());
        if (first < 0 || first > 7)
        {
            fail("pattern hexadecimal escapes must encode ASCII");
            return -1;
        }

        ++offset;
        immutable second = hexValue(peek());
        if (second < 0)
        {
            fail("expected two hexadecimal digits in pattern escape");
            return -1;
        }
        ++offset;
        return first * 16 + second;
    }

    private ushort fail(string message) pure nothrow @nogc
    {
        if (error is null)
            error = message;
        return 0;
    }
}

private int hexValue()(int ch) pure nothrow @nogc
{
    if (ch >= '0' && ch <= '9')
        return ch - '0';
    if (ch >= 'A' && ch <= 'F')
        return ch - 'A' + 10;
    if (ch >= 'a' && ch <= 'f')
        return ch - 'a' + 10;
    return -1;
}

private Selection shorthand()(int ch) pure nothrow @nogc
{
    Selection mask;
    switch (ch | 0x20)
    {
    case 's':
        mask.include('\t', '\r');
        mask.include(' ', ' ');
        break;
    case 'w':
        mask.include('A', 'Z');
        mask.include('a', 'z');
        mask.include('_', '_');
        goto case;
    case 'd':
        mask.include('0', '9');
        break;
    default:
        assert(0, "invalid pattern shorthand");
    }
    if (ch < 'a')
        mask.invert();
    return mask;
}

private struct Instruction
{
    Op op;
    ushort next;
    ushort branch;
    Selection selection;
}

private struct Program()
{
    Instruction[stateLimit] states;
    ushort count;
    ushort entry;
    string error;

    ushort append(Instruction state) pure nothrow @nogc
    {
        if (count == states.length)
        {
            error = "pattern exceeds 256 NFA states";
            return 0;
        }
        states[count] = state;
        return count++;
    }

    ushort lower(scope const(Term)[] terms, ushort index, ushort next) pure nothrow @nogc
    {
        if (error !is null)
            return 0;

        const term = terms[index];
        switch (term.op)
        {
        case Op.empty:
            return next;
        case Op.sequence:
            immutable right = lower(terms, term.second, next);
            return lower(terms, term.first, right);
        case Op.choice:
            immutable first = lower(terms, term.first, next);
            immutable second = lower(terms, term.second, next);
            return append(Instruction(Op.choice, first, second));
        case Op.repeat:
            return repeatTerm(terms, term, next);
        default:
            return append(Instruction(term.op, next, term.first, term.selection));
        }
    }

    private ushort repeatTerm(scope const(Term)[] terms, Term term, ushort next) pure nothrow @nogc
    {
        ushort required = term.minimum;
        if (term.maximum == unbounded)
        {
            immutable branch = append(Instruction(Op.choice, 0, next));
            immutable loopStart = lower(terms, term.first, branch);
            states[branch].next = loopStart;
            next = branch;
            if (required > 0)
            {
                next = loopStart;
                --required;
            }
        }
        else
        {
            foreach (_; term.minimum .. term.maximum)
            {
                immutable option = lower(terms, term.first, next);
                if (option != next)
                    next = append(Instruction(Op.choice, option, next));
                if (error !is null)
                    return 0;
            }
        }

        foreach (_; 0 .. required)
            next = lower(terms, term.first, next);
        return next;
    }
}

private Program!() compilePattern(string expression)()
{
    if (expression.length > 4_096)
    {
        Program!() failure;
        failure.error = "pattern exceeds 4096 source bytes";
        return failure;
    }

    RegexParser!(expression.length > 4_096 ? 1 : 2 * expression.length + 1) parser;
    parser.expression = expression;
    parser.add(Term(Op.empty));
    immutable syntax = parser.parse();

    Program!() program;
    if (parser.error !is null || parser.offset != expression.length)
    {
        program.error = parser.error is null ? "unmatched pattern group delimiter" : parser.error;
        return program;
    }
    program.append(Instruction(Op.accept));
    program.entry = program.lower(parser.terms[0 .. parser.termCount], syntax, 0);
    return program;
}

private template PatternCode(string expression)
{
    enum compiled = compilePattern!expression();
    static immutable instructions = compiled.states[0 .. compiled.count];
}

/// A pattern compiled at run time, for expressions that arrive as data (Flint AOT descriptors of
/// Jakarta `@Pattern`). Same syntax, limits and automaton as the compile-time patterns, plus java.util.regex's
/// `\p{L}`/`\P{L}` letter category.
package(flint) struct RuntimePattern
{
    private Instruction[] code;
    private ushort entry;
    /// The compile error, or null when the pattern compiled.
    string error;

    /// Whether `bytes` matches the whole pattern; false when it did not compile.
    bool matches(scope const(ubyte)[] bytes) const pure nothrow @nogc
    {
        return error is null && match(code, entry, bytes);
    }
}

/// Compile `expression` at run time. The parser's term buffer is sized for the 4,096-byte limit and lives on
/// the GC heap, so callers compile each expression once and keep the result. A template, so its GC allocations
/// are generated only where it is called: DMD otherwise emits them in every -betterC build of this module.
package(flint) RuntimePattern compileRuntimePattern()(string expression)
{
    RuntimePattern result;
    if (expression.length > 4_096)
    {
        result.error = "pattern exceeds 4096 source bytes";
        return result;
    }
    auto parser = new RegexParser!(2 * 4_096 + 1);
    parser.expression = expression;
    parser.unicodeProperties = true;
    parser.add(Term(Op.empty));
    immutable syntax = parser.parse();
    if (parser.error !is null || parser.offset != expression.length)
    {
        result.error = parser.error is null ? "unmatched pattern group delimiter" : parser.error;
        return result;
    }
    auto program = new Program!();
    program.append(Instruction(Op.accept));
    program.entry = program.lower(parser.terms[0 .. parser.termCount], syntax, 0);
    if (program.error !is null)
    {
        result.error = program.error;
        return result;
    }
    result.code = program.states[0 .. program.count].dup;
    result.entry = program.entry;
    return result;
}

package(flint.validate) enum patternError(string expression) = PatternCode!expression.compiled.error;

package(flint.validate) bool matchPattern(string expression)(scope const(ubyte)[] bytes) pure nothrow @nogc
{
    alias Code = PatternCode!expression;
    return match(Code.instructions, Code.compiled.entry, bytes);
}

private struct StateSet
{
    ulong[stateLimit / 64] flags;
    ushort[stateLimit] order;
    size_t count;

    bool contains(ushort index) const pure nothrow @nogc
    {
        return (flags[index >> 6] & (1UL << (index & 63))) != 0;
    }

    void insert(ushort index) pure nothrow @nogc
    {
        if (contains(index))
            return;
        flags[index >> 6] |= 1UL << (index & 63);
        order[count++] = index;
    }

    void clear() pure nothrow @nogc
    {
        flags[] = 0;
        count = 0;
    }

    void expand(scope const(Instruction)[] instructions, bool beginning, bool ending) pure nothrow @nogc
    {
        foreach (size_t index; 0 .. stateLimit)
        {
            if (index == count)
                break;
            const instruction = instructions[order[index]];
            switch (instruction.op)
            {
            case Op.choice:
                insert(instruction.branch);
                insert(instruction.next);
                break;
            case Op.begin:
                if (beginning)
                    insert(instruction.next);
                break;
            case Op.end:
                if (ending)
                    insert(instruction.next);
                break;
            default:
                break;
            }
        }
    }

    void consume(scope const(Instruction)[] code, uint scalar, ref scope StateSet target) const pure nothrow @nogc
    {
        foreach (active; order[0 .. count])
        {
            const instruction = code[active];
            if (accepts(instruction, scalar))
                target.insert(instruction.next);
        }
    }
}

private bool accepts(scope ref const Instruction instruction, uint scalar) pure nothrow @nogc
{
    switch (instruction.op)
    {
    case Op.literal:
        return scalar == instruction.branch;
    case Op.any:
        return scalar != '\n';
    case Op.selection:
        return instruction.selection.contains(scalar);
    default:
        return false;
    }
}

private bool match(scope const(Instruction)[] instructions, ushort entry, scope const(ubyte)[] bytes) pure nothrow @nogc
{
    if (bytes.length > byteLimit)
        return false;

    StateSet[2] active;
    size_t slot;
    active[slot].insert(entry);
    active[slot].expand(instructions, true, bytes.length == 0);
    for (size_t offset; offset < bytes.length;)
    {
        immutable scalar = decodeScalar(bytes, offset);
        if (scalar < 0)
            return false;

        immutable next = slot ^ 1;
        active[next].clear();
        active[slot].consume(instructions, cast(uint) scalar, active[next]);
        if (active[next].count == 0)
            return false;

        active[next].expand(instructions, false, offset == bytes.length);
        slot = next;
    }
    return active[slot].contains(0);
}

@("run-time patterns match java.util.regex's \\p{L} and \\P{L}; compile-time patterns still reject them")
unittest
{
    static assert(patternError!`\p{L}` !is null);
    auto name = compileRuntimePattern(`^[\p{L}]+([ '-][\p{L}]+){0,2}$`);
    assert(name.error is null);
    foreach (accepted; ["Ada", "José María", "李", "\U0001D49Cda", "O'Brien-Núñez"])
        assert(name.matches(cast(const(ubyte)[]) accepted), accepted);
    foreach (rejected; ["Ada2", "Ελένη 2", "Renée", "", "a  b"])
        assert(!name.matches(cast(const(ubyte)[]) rejected), rejected);
    auto others = compileRuntimePattern(`\P{L}+`);
    assert(others.matches(cast(const(ubyte)[]) "12 ́") && !others.matches(cast(const(ubyte)[]) "12é"));
    auto mixed = compileRuntimePattern(`[\p{L}\P{L}]`);
    assert(mixed.matches(cast(const(ubyte)[]) " ") && mixed.matches(cast(const(ubyte)[]) "é"));
    assert(compileRuntimePattern(`\p{Lu}`).error !is null);
    assert(compileRuntimePattern(`\pL+`).matches(cast(const(ubyte)[]) "Zoë"));
}
