/// The YAML engine behind `YamlPropertySourceLoader` (Boot reads YAML with SnakeYAML; Flint's engine is D).
///
/// It reads what Boot configuration uses: block mappings and sequences (including compact `- key: value`
/// entries and sequences at their key's indentation), plain, single- and double-quoted scalars that may span lines,
/// literal `|` and folded `>` block scalars with chomping and indentation indicators, flow `[...]` and `{...}`
/// collections, comments, multiple documents (`---`, `...`), anchors, aliases and `<<` merge keys, and the core
/// `!!` tags. Scalars are resolved as SnakeYAML's YAML 1.1 resolver resolves them for Boot, then turned back into
/// text: `True`, `yes` and `on` read as `true`, `~` and `null` as an empty value, `0x1A` as `26`, `1_000` as `1000`.
/// Every scalar keeps its zero-based line and column for origin tracking. Unknown tags (`!!java.net.URL`) are
/// rejected, as Boot's restricted constructor rejects them. Timestamps stay text, as Boot's resolver leaves them.
module flint.boot.internal.yaml;

import flint.java.lang : RuntimeException;

@safe:

/// A YAML syntax or composition error, with the one-based position where it was detected.
final class YamlException : RuntimeException
{
    /// The message, already carrying the position.
    this(string message) pure
    {
        super(message);
    }
}

/// A parsed YAML node.
final class YamlNode
{
    /// What the node is.
    enum Kind
    {
        /// An empty or `null` value.
        empty,
        /// A scalar.
        scalar,
        /// A mapping, with keys in document order.
        mapping,
        /// A sequence.
        sequence
    }

    /// The node's kind.
    Kind kind;
    /// A scalar's resolved text.
    string value;
    /// Zero-based position of the node's first character.
    int line;
    /// ditto
    int column;
    /// A mapping's keys, in order.
    string[] keys;
    /// A mapping's values, parallel to `keys`, or a sequence's items.
    YamlNode[] items;

    /// A node of `kind` at the given position.
    this(Kind kind, int line, int column) pure nothrow
    {
        this.kind = kind;
        this.line = line;
        this.column = column;
    }

    /// Set or replace the value of mapping key `key`.
    void put(string key, YamlNode value) pure nothrow
    {
        foreach (index, existing; keys)
        {
            if (existing == key)
            {
                items[index] = value;
                return;
            }
        }
        keys ~= key;
        items ~= value;
    }
}

/// Parse every document of `text`. Empty documents give `null` entries.
YamlNode[] parseYaml(string text) pure
{
    auto parser = Parser(text);
    return parser.documents();
}

private struct Parser
{
    string[] lines;
    size_t row;
    size_t col;
    YamlNode[string] anchors;

    this(string text) pure
    {
        import flint.boot.internal.text : replace = replaced;
        import flint.boot.internal.text : split = pieces;

        auto normalized = text.replace("\r\n", "\n").replace("\r", "\n");
        if (normalized.length >= 3 && normalized[0 .. 3] == "\xEF\xBB\xBF")
            normalized = normalized[3 .. $];
        lines = normalized.split('\n');
    }

    YamlNode[] documents() pure
    {
        YamlNode[] result;
        bool explicitStart;
        while (true)
        {
            skipBlank();
            if (row >= lines.length)
                break;
            const line = lines[row];
            if (line.length && line[0] == '%')
            {
                row++;
                continue;
            }
            if (isMarker(line, "---"))
            {
                // A document marker; content may follow it on the same line.
                explicitStart = true;
                col = 3;
                skipSpaces();
                if (atLineEnd())
                {
                    row++;
                    col = 0;
                    result ~= documentBody();
                }
                else
                    result ~= documentBody();
                continue;
            }
            if (isMarker(line, "..."))
            {
                row++;
                col = 0;
                continue;
            }
            result ~= documentBody();
        }
        return result;
    }

    YamlNode documentBody() pure
    {
        anchors = null;
        skipBlank();
        if (row >= lines.length || startsDocumentBoundary())
            return null;
        auto node = blockNode(-1);
        skipBlank();
        if (row < lines.length && !startsDocumentBoundary())
            fail("expected a document boundary or the end of the stream");
        return node.kind == YamlNode.Kind.empty ? null : node;
    }

    bool startsDocumentBoundary() const pure nothrow @nogc
    {
        return row < lines.length && col == 0 && (isMarker(lines[row], "---") || isMarker(lines[row], "..."));
    }

    static bool isMarker(string line, string marker) pure nothrow @nogc
    {
        return line.length >= 3 && line[0 .. 3] == marker && (line.length == 3 || line[3] == ' ' || line[3] == '\t');
    }

    // ---- cursor helpers -------------------------------------------------------------------------------------------

    void skipSpaces() pure nothrow @nogc
    {
        while (row < lines.length && col < lines[row].length && (lines[row][col] == ' ' || lines[row][col] == '\t'))
            col++;
    }

    bool atLineEnd() const pure nothrow @nogc
    {
        if (row >= lines.length)
            return true;
        const line = lines[row];
        return col >= line.length || (line[col] == '#' && (col == 0 || line[col - 1] == ' ' || line[col - 1] == '\t'));
    }

    // Move to the first non-blank, non-comment line at column 0 of that line (cursor at indentation).
    void skipBlank() pure nothrow @nogc
    {
        if (row < lines.length && col > 0)
        {
            skipSpaces();
            if (!atLineEnd())
                return;
            row++;
            col = 0;
        }
        while (row < lines.length)
        {
            const indent = indentOf(lines[row]);
            if (indent < lines[row].length && lines[row][indent] != '#')
                return;
            row++;
        }
    }

    static size_t indentOf(string line) pure nothrow @nogc
    {
        size_t i;
        while (i < line.length && line[i] == ' ')
            i++;
        if (i < line.length && line[i] == '\t')
        {
            // Tabs may separate but not indent; treat a tab-led line as blank-led for structure.
            while (i < line.length && (line[i] == ' ' || line[i] == '\t'))
                i++;
        }
        return i;
    }

    // The column of the next significant content: the current position when mid-line, else the next line's indent.
    long nextIndent() pure nothrow @nogc
    {
        skipBlank();
        if (row >= lines.length || startsDocumentBoundary())
            return -1;
        if (col == 0)
            col = indentOf(lines[row]);
        return cast(long) col;
    }

    noreturn fail(string message) const pure
    {
        import flint.engine.aot.text : decimal;

        throw new YamlException(message ~ " (line " ~ decimal(row + 1) ~ ", column " ~ decimal(col + 1) ~ ")");
    }

    char peek(size_t offset = 0) const pure nothrow @nogc
    {
        if (row >= lines.length)
            return 0;
        const line = lines[row];
        return col + offset < line.length ? line[col + offset] : 0;
    }

    // ---- block structure ------------------------------------------------------------------------------------------

    // A node whose content is indented more than `parent`, starting at the next significant position.
    YamlNode blockNode(long parent) pure
    {
        const indent = nextIndent();
        if (indent <= parent)
            return new YamlNode(YamlNode.Kind.empty, cast(int) row, cast(int) col);
        return nodeAt(parent);
    }

    // The node whose first character is at the cursor, inside a parent at column `parent`.
    YamlNode nodeAt(long parent) pure
    {
        string anchor;
        string tag;
        properties(anchor, tag);
        if (atLineEnd() && (anchor.length || tag.length))
        {
            // `&a` or `!!map` alone on its line: the node follows on the next lines.
            const r = row, c = col;
            row++;
            col = 0;
            auto node = blockNode(parent);
            if (node.kind == YamlNode.Kind.empty)
            {
                node.line = cast(int) r;
                node.column = cast(int) c;
            }
            return finish(node, anchor, tag);
        }
        if (peek() == '*')
            return alias_();
        if (peek() == '-' && (peek(1) == ' ' || peek(1) == '\t' || peek(1) == 0))
            return finish(sequence(col), anchor, tag);
        if (looksLikeKey())
            return finish(mapping(col), anchor, tag);
        return finish(inlineValue(parent), anchor, tag);
    }

    YamlNode finish(YamlNode node, string anchor, string tag) pure
    {
        node = applyTag(node, tag);
        if (anchor.length)
            anchors[anchor] = node;
        return node;
    }

    void properties(ref string anchor, ref string tag) pure
    {
        while (true)
        {
            skipSpaces();
            if (peek() == '&')
            {
                col++;
                anchor = word();
            }
            else if (peek() == '!')
                tag = word();
            else
                return;
        }
    }

    string word() pure
    {
        const line = lines[row];
        const start = col;
        while (col < line.length && line[col] != ' ' && line[col] != '\t' && line[col] != ','
                && line[col] != ']' && line[col] != '}')
            col++;
        if (col == start)
            fail("expected a name");
        return line[start .. col];
    }

    YamlNode alias_() pure
    {
        col++;
        const name = word();
        if (auto node = name in anchors)
            return *node;
        fail("found undefined alias '" ~ name ~ "'");
    }

    YamlNode applyTag(YamlNode node, string tag) pure
    {
        switch (tag)
        {
        case "":
        case "!":
        case "!!map":
        case "!!seq":
        case "!!int":
        case "!!float":
        case "!!bool":
        case "!!null":
        case "!!binary":
        case "!!timestamp":
            return node;
        case "!!str":
            if (node.kind == YamlNode.Kind.scalar || node.kind == YamlNode.Kind.empty)
            {
                node.value = rawValues.get(cast(size_t) node.line * 100_000 + node.column,
                        node.value is null ? "" : node.value);
                node.kind = YamlNode.Kind.scalar;
            }
            return node;
        default:
            fail("could not determine a constructor for the tag " ~ tag);
        }
    }

    string[size_t] rawValues;

    bool looksLikeKey() const pure
    {
        // A plain or quoted key followed by `:` and a space or the line end, on this line.
        const line = lines[row];
        size_t i = col;
        if (i >= line.length)
            return false;
        if (line[i] == '"' || line[i] == '\'')
        {
            i = quoteEnd(line, i);
            while (i < line.length && blank(line[i]))
                i++;
            return valueIndicator(line, i);
        }
        if (startsNonKey(line, i))
            return false;
        for (; i < line.length; i++)
        {
            if (line[i] == '#' && i > 0 && blank(line[i - 1]))
                return false;
            if (valueIndicator(line, i))
                return true;
        }
        return false;
    }

    YamlNode mapping(size_t indent) pure
    {
        auto node = new YamlNode(YamlNode.Kind.mapping, cast(int) row, cast(int) col);
        YamlNode[] merges;
        while (true)
        {
            if (peek() == '?')
                fail("complex mapping keys are not supported");
            if (!looksLikeKey())
                fail("expected a mapping key");
            const key = scalarKey();
            skipSpaces();
            if (peek() != ':')
                fail("expected ':'");
            col++;
            skipSpaces();
            YamlNode value;
            if (atLineEnd())
            {
                row++;
                col = 0;
                const next = nextIndent();
                if (next > cast(long) indent)
                    value = nodeAt(indent);
                else if (next == cast(long) indent && peek() == '-' && (peek(1) == ' ' || peek(1) == 0))
                    value = sequence(cast(size_t) next);
                else
                    value = new YamlNode(YamlNode.Kind.empty, cast(int) row, cast(int) col);
            }
            else
                value = nodeAt(indent);
            if (key == "<<")
                merges ~= value;
            else
                node.put(key, value);
            const next = nextIndent();
            if (next != cast(long) indent || (peek() == '-' && (peek(1) == ' ' || peek(1) == 0)))
                break;
        }
        foreach (merge; merges)
            mergeInto(node, merge);
        return node;
    }

    void mergeInto(YamlNode node, YamlNode merge) pure
    {
        if (merge.kind == YamlNode.Kind.sequence)
        {
            foreach (item; merge.items)
                mergeInto(node, item);
            return;
        }
        if (merge.kind != YamlNode.Kind.mapping)
            fail("expected a mapping or a list of mappings for merging");
        foreach (index, key; merge.keys)
        {
            bool present;
            foreach (existing; node.keys)
                present = present || existing == key;
            if (!present)
                node.put(key, merge.items[index]);
        }
    }

    string scalarKey() pure
    {
        if (peek() == '"' || peek() == '\'')
        {
            auto quoted = quotedScalar();
            return quoted.value;
        }
        const line = lines[row];
        const start = col;
        while (col < line.length && !(line[col] == ':' && (col + 1 == line.length
                || line[col + 1] == ' ' || line[col + 1] == '\t')))
            col++;
        import flint.boot.internal.text : stripRight = stripTrailing;

        return resolve(line[start .. col].stripRight, false);
    }

    YamlNode sequence(size_t indent) pure
    {
        auto node = new YamlNode(YamlNode.Kind.sequence, cast(int) row, cast(int) col);
        while (true)
        {
            col++; // past '-'
            skipSpaces();
            YamlNode item;
            if (atLineEnd())
            {
                row++;
                col = 0;
                item = blockNode(indent);
            }
            else
                item = nodeAt(indent);
            node.items ~= item;
            const next = nextIndent();
            if (next != cast(long) indent || !(peek() == '-' && (peek(1) == ' ' || peek(1) == '\t' || peek(1) == 0)))
                break;
        }
        return node;
    }

    // ---- scalars and flow collections ---------------------------------------------------------------------------

    YamlNode inlineValue(long parent) pure
    {
        const c = peek();
        if (c == '|' || c == '>')
            return blockScalar(parent);
        if (c == '"' || c == '\'')
        {
            auto node = quotedScalar();
            skipSpaces();
            if (!atLineEnd())
                fail("unexpected content after a quoted scalar");
            return node;
        }
        if (c == '[' || c == '{')
        {
            auto node = flowNode();
            skipSpaces();
            if (!atLineEnd())
                fail("unexpected content after a flow collection");
            return node;
        }
        return plainScalar(parent);
    }

    YamlNode plainScalar(long parent) pure
    {
        auto node = new YamlNode(YamlNode.Kind.scalar, cast(int) row, cast(int) col);
        string text = lineValue();
        // Continuation lines, indented more than the parent, fold into one line.
        while (true)
        {
            const save = row;
            size_t blankLines;
            if (!continuationLine(parent, blankLines))
            {
                row = save;
                break;
            }
            const more = lineValue();
            text ~= blankLines ? newlines(blankLines) : " ";
            text ~= more;
        }
        col = lines[row].length;
        return resolvedScalar(node, text);
    }

    // Move to the next line that continues a plain scalar, counting the blank lines skipped.
    bool continuationLine(long parent, ref size_t blankLines) pure
    {
        import flint.engine.aot.text : strip = stripWhite;

        row++;
        col = 0;
        while (row < lines.length && lines[row].strip.length == 0)
        {
            blankLines++;
            row++;
        }
        if (row >= lines.length || startsDocumentBoundary())
            return false;
        const line = lines[row];
        const indent = indentOf(line);
        col = indent;
        if (cast(long) indent <= parent || line[indent] == '#' || looksLikeKey())
            return false;
        return !(line[indent] == '-' && (indent + 1 == line.length || line[indent + 1] == ' '));
    }

    YamlNode resolvedScalar(YamlNode node, string text) pure
    {
        rawValues[positionKey(node)] = text;
        node.value = resolve(text, true);
        if (node.value is null)
            node.kind = YamlNode.Kind.empty;
        return node;
    }

    static size_t positionKey(const YamlNode node) pure nothrow @nogc
    {
        return cast(size_t) node.line * 100_000 + node.column;
    }

    // The rest of the current line up to a comment, trimmed.
    string lineValue() pure
    {
        import flint.boot.internal.text : stripRight = stripTrailing;

        const line = lines[row];
        const start = col;
        size_t end = col;
        while (end < line.length && !(line[end] == '#' && end > start && blank(line[end - 1])))
            end++;
        col = end;
        return line[start .. end].stripRight;
    }

    YamlNode quotedScalar() pure
    {
        auto node = new YamlNode(YamlNode.Kind.scalar, cast(int) row, cast(int) col);
        const quote = peek();
        col++;
        string text;
        while (true)
        {
            if (row >= lines.length)
                fail("found unexpected end of stream while scanning a quoted scalar");
            const line = lines[row];
            if (col >= line.length)
            {
                foldQuotedLine(text);
                continue;
            }
            if (quote == '\'' ? singleQuoted(line, text) : doubleQuoted(line, text))
                break;
        }
        node.value = text;
        rawValues[positionKey(node)] = text;
        return node;
    }

    // Line folding inside quotes: trailing spaces dropped, one line break becomes a space, blank lines newlines.
    void foldQuotedLine(ref string text) pure
    {
        import flint.boot.internal.text : stripRight = stripTrailing;

        text = text.stripRight;
        row++;
        col = 0;
        size_t blankLines;
        while (row < lines.length && indentOf(lines[row]) == lines[row].length)
        {
            blankLines++;
            row++;
        }
        if (row >= lines.length)
            fail("found unexpected end of stream while scanning a quoted scalar");
        col = indentOf(lines[row]);
        text ~= blankLines ? newlines(blankLines) : " ";
    }

    // One step of a single-quoted scalar; true at the closing quote.
    bool singleQuoted(string line, ref string text) pure
    {
        const ch = line[col];
        if (ch != '\'')
        {
            text ~= ch;
            col++;
            return false;
        }
        if (col + 1 < line.length && line[col + 1] == '\'')
        {
            text ~= '\'';
            col += 2;
            return false;
        }
        col++;
        return true;
    }

    // One step of a double-quoted scalar; true at the closing quote.
    bool doubleQuoted(string line, ref string text) pure
    {
        const ch = line[col];
        if (ch == '"')
        {
            col++;
            return true;
        }
        if (ch != '\\')
        {
            text ~= ch;
            col++;
            return false;
        }
        col++;
        if (col < line.length)
        {
            text ~= escape(line);
            return false;
        }
        // An escaped line break joins lines without a space.
        row++;
        col = row < lines.length ? indentOf(lines[row]) : 0;
        return false;
    }

    string escape(string line) pure
    {
        const ch = line[col++];
        if (auto simple = simpleEscape(ch))
            return simple;
        if (ch == 'x' || ch == 'u' || ch == 'U')
            return unicodeEscape(line, ch == 'x' ? 2 : (ch == 'u' ? 4 : 8));
        fail("found unknown escape character '" ~ ch ~ "'");
    }

    string unicodeEscape(string line, size_t digits) pure
    {
        import flint.boot.internal.text : parseUnsigned;
        import flint.engine.aot.text : decimal, utf8;

        if (col + digits > line.length)
            fail("expected escape sequence of " ~ decimal(digits) ~ " hexadecimal numbers");
        ulong code;
        if (!parseUnsigned(line[col .. col + digits], 16, uint.max, code))
            fail("expected escape sequence of " ~ decimal(digits) ~ " hexadecimal numbers");
        col += digits;
        const text = utf8(cast(dchar) code);
        if (text is null)
            fail("found invalid Unicode character escape code");
        return text;
    }

    YamlNode blockScalar(long parent) pure
    {
        auto node = new YamlNode(YamlNode.Kind.scalar, cast(int) row, cast(int) col);
        const folded = peek() == '>';
        col++;
        const indicators = blockIndicators();
        const chomp = indicators.chomp;
        const explicitIndent = indicators.indent;
        row++;
        col = 0;
        const indent = explicitIndent ? cast(size_t)(parent < 0 ? 0 : parent) + explicitIndent : firstContentIndent();
        string[] content = blockLines(indent, parent);
        size_t trailing;
        while (content.length && content[$ - 1].length == 0)
        {
            content = content[0 .. $ - 1];
            trailing++;
        }
        string text = folded ? foldLines(content) : joinLines(content);
        if (chomp == '+')
            text ~= newlines((content.length ? 1 : 0) + trailing);
        else if (chomp == 'c' && content.length)
            text ~= "\n";
        node.value = text;
        rawValues[positionKey(node)] = text;
        return node;
    }

    static struct Indicators
    {
        char chomp = 'c';
        size_t indent;
    }

    Indicators blockIndicators() pure
    {
        Indicators result;
        foreach (_; 0 .. 2)
        {
            const c = peek();
            if (c == '+' || c == '-')
            {
                result.chomp = c;
                col++;
            }
            else if (c >= '1' && c <= '9')
            {
                result.indent = c - '0';
                col++;
            }
        }
        skipSpaces();
        if (!atLineEnd())
            fail("expected a comment or a line break after a block scalar indicator");
        return result;
    }

    size_t firstContentIndent() const pure nothrow @nogc
    {
        foreach (r; row .. lines.length)
        {
            if (indentOf(lines[r]) < lines[r].length)
                return leadingSpaces(lines[r]);
        }
        return 0;
    }

    // The block scalar's lines, without their indentation; the cursor stays on the last line consumed.
    string[] blockLines(size_t indent, long parent) pure
    {
        string[] content;
        while (row < lines.length)
        {
            const line = lines[row];
            const spaces = leadingSpaces(line);
            const empty = spaces == line.length;
            if (!empty && (spaces < indent || cast(long) spaces <= parent || startsDocumentBoundary()))
                break;
            content ~= line.length > indent ? line[indent .. $] : "";
            row++;
        }
        if (row > 0)
            row--;
        col = lines.length ? lines[row].length : 0;
        return content;
    }

    static string joinLines(string[] content) pure
    {
        import flint.boot.internal.text : join = joined;

        return content.join("\n");
    }

    // YAML folding: a line break between two plain lines becomes a space; empty lines and more-indented lines
    // keep their line breaks.
    static string foldLines(string[] content) pure
    {
        string text;
        foreach (index, line; content)
        {
            if (index > 0)
                text ~= foldSeparator(content[index - 1], line);
            text ~= line;
        }
        return text;
    }

    static string foldSeparator(string previous, string line) pure nothrow @nogc
    {
        if (line.length == 0)
            return "\n";
        if (previous.length == 0)
            return ""; // the empty lines before this one already produced its line breaks
        if (blank(line[0]) || blank(previous[0]))
            return "\n";
        return " ";
    }

    static size_t leadingSpaces(string line) pure nothrow @nogc
    {
        size_t i;
        while (i < line.length && line[i] == ' ')
            i++;
        return i;
    }

    // Flow collections may span lines; newlines count as spaces.
    void flowSpace() pure
    {
        while (true)
        {
            skipSpaces();
            if (row >= lines.length)
                fail("found unexpected end of stream in a flow collection");
            if (!atLineEnd())
                return;
            row++;
            col = 0;
        }
    }

    YamlNode flowNode() pure
    {
        flowSpace();
        string anchor, tag;
        while (peek() == '&' || peek() == '!')
        {
            if (peek() == '&')
            {
                col++;
                anchor = word();
            }
            else
                tag = word();
            flowSpace();
        }
        YamlNode node;
        switch (peek())
        {
        case '*':
            node = alias_();
            break;
        case '[':
            node = flowSequence();
            break;
        case '{':
            node = flowMapping();
            break;
        case '"':
        case '\'':
            node = quotedScalar();
            break;
        default:
            node = flowPlain();
        }
        return finish(node, anchor, tag);
    }

    YamlNode flowSequence() pure
    {
        auto node = new YamlNode(YamlNode.Kind.sequence, cast(int) row, cast(int) col);
        col++;
        flowSpace();
        while (peek() != ']')
        {
            auto item = flowNode();
            flowSpace();
            if (peek() == ':')
            {
                // `[a: b]` is a single-pair mapping.
                col++;
                auto pair = new YamlNode(YamlNode.Kind.mapping, item.line, item.column);
                pair.put(item.value, flowNode());
                item = pair;
                flowSpace();
            }
            node.items ~= item;
            flowSeparator(']');
        }
        col++;
        return node;
    }

    YamlNode flowMapping() pure
    {
        auto node = new YamlNode(YamlNode.Kind.mapping, cast(int) row, cast(int) col);
        col++;
        flowSpace();
        while (peek() != '}')
        {
            auto key = flowNode();
            flowSpace();
            YamlNode value = new YamlNode(YamlNode.Kind.empty, key.line, key.column);
            if (peek() == ':')
            {
                col++;
                flowSpace();
                if (peek() != ',' && peek() != '}')
                    value = flowNode();
                flowSpace();
            }
            node.put(key.value, value);
            flowSeparator('}');
        }
        col++;
        return node;
    }

    void flowSeparator(char close) pure
    {
        if (peek() == ',')
        {
            col++;
            flowSpace();
        }
        else if (peek() != close)
            fail("expected ',' or '" ~ close ~ "'");
    }

    YamlNode flowPlain() pure
    {
        import flint.boot.internal.text : stripRight = stripTrailing;

        auto node = new YamlNode(YamlNode.Kind.scalar, cast(int) row, cast(int) col);
        const line = lines[row];
        const start = col;
        while (col < line.length && !flowPlainEnds(line, col, start))
            col++;
        return resolvedScalar(node, line[start .. col].stripRight);
    }

    static bool flowPlainEnds(string line, size_t i, size_t start) pure nothrow @nogc
    {
        const ch = line[i];
        if (ch == ',' || ch == ']' || ch == '}')
            return true;
        if (ch == '#')
            return i > start && line[i - 1] == ' ';
        if (ch != ':')
            return false;
        if (i + 1 == line.length)
            return true;
        const next = line[i + 1];
        return next == ' ' || next == ',' || next == ']' || next == '}';
    }
}

/// Resolve a plain scalar as SnakeYAML's YAML 1.1 resolver does, back to text. Returns `null` for null values
/// when `nulls` is set.
string resolve(string text, bool nulls) pure
{
    if (nulls && isNull(text))
        return null;
    if (const boolean = booleanText(text))
        return boolean;
    if (text.length && isIntegerText(text))
        return integerText(text);
    return text;
}

private bool isNull(string text) pure nothrow @nogc
{
    return text.length == 0 || text == "~" || text == "null" || text == "Null" || text == "NULL";
}

// YAML 1.1 booleans as SnakeYAML resolves them, or `null`.
private string booleanText(string text) pure nothrow @nogc
{
    static immutable truths = ["yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON"];
    static immutable falsehoods = ["no", "No", "NO", "false", "False", "FALSE", "off", "Off", "OFF"];
    foreach (word; truths)
    {
        if (text == word)
            return "true";
    }
    foreach (word; falsehoods)
    {
        if (text == word)
            return "false";
    }
    return null;
}

// An integer in YAML 1.1 notation (sign, `0b`, `0x`, leading-0 octal, `_` separators) as decimal text.
private string integerText(string text) pure
{
    import flint.boot.internal.text : parseUnsigned, replace = replaced;
    import flint.engine.aot.text : decimal;

    string digits = text.replace("_", "");
    string sign;
    if (digits[0] == '-' || digits[0] == '+')
    {
        sign = digits[0] == '-' ? "-" : "";
        digits = digits[1 .. $];
    }
    // std.conv's radix forms: within long; the decimal one within ulong. Anything else stays as written.
    ulong value;
    bool parsed;
    if (digits.length > 2 && digits[0 .. 2] == "0x")
        parsed = parseUnsigned(digits[2 .. $], 16, long.max, value);
    else if (digits.length > 2 && digits[0 .. 2] == "0b")
        parsed = parseUnsigned(digits[2 .. $], 2, long.max, value);
    else if (digits.length > 1 && digits[0] == '0')
        parsed = parseUnsigned(digits[1 .. $], 8, long.max, value);
    else
        parsed = parseUnsigned(digits, 10, ulong.max, value);
    return parsed ? sign ~ decimal(value) : text;
}

private bool isIntegerText(string text) pure nothrow @nogc
{
    const start = (text[0] == '-' || text[0] == '+') ? 1 : 0;
    if (start >= text.length || text[start] == '_')
        return false;
    const number = text[start .. $];
    if (number.length > 2 && number[0] == '0' && (number[1] == 'x' || number[1] == 'b'))
        return allDigits(number[2 .. $], number[1] == 'x' ? 16 : 2);
    return allDigits(number, number[0] == '0' && number.length > 1 ? 8 : 10);
}

private bool allDigits(string digits, uint radix) pure nothrow @nogc
{
    foreach (ch; digits)
    {
        if (ch != '_' && digitValue(ch) >= radix)
            return false;
    }
    return true;
}

private uint digitValue(char ch) pure nothrow @nogc
{
    if (ch >= '0' && ch <= '9')
        return ch - '0';
    if (ch >= 'a' && ch <= 'f')
        return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F')
        return ch - 'A' + 10;
    return uint.max;
}

private string newlines(size_t count) pure
{
    string text;
    foreach (_; 0 .. count)
        text ~= "\n";
    return text;
}

// Escapes that stand for one fixed string, or `null`.
private string simpleEscape(char ch) pure nothrow @nogc
{
    static immutable char[] codes = "0abt\tnvfre \"/\\";
    static immutable string[] texts = [
        "\0", "\a", "\b", "\t", "\t", "\n", "\v", "\f", "\r", "\x1B", " ", "\"", "/", "\\"
    ];
    foreach (index, code; codes)
    {
        if (code == ch)
            return texts[index];
    }
    return lineBreakEscape(ch);
}

private string lineBreakEscape(char ch) pure nothrow @nogc
{
    switch (ch)
    {
    case 'N':
        return "\u0085";
    case '_':
        return " ";
    case 'L':
        return "
";
    case 'P':
        return "
";
    default:
        return null;
    }
}

private bool blank(char ch) pure nothrow @nogc
{
    return ch == ' ' || ch == '\t';
}

// Whether `line[i]` is a `:` that introduces a value: followed by a blank or the line end.
private bool valueIndicator(string line, size_t i) pure nothrow @nogc
{
    return i < line.length && line[i] == ':' && (i + 1 == line.length || blank(line[i + 1]));
}

// The index just past the quoted scalar that starts at `line[start]`.
private size_t quoteEnd(string line, size_t start) pure nothrow @nogc
{
    const quote = line[start];
    size_t i = start + 1;
    while (i < line.length)
    {
        if (line[i] == '\\' && quote == '"')
            i += 2;
        else if (line[i] != quote)
            i++;
        else if (quote == '\'' && i + 1 < line.length && line[i + 1] == '\'')
            i += 2;
        else
            break;
    }
    return i + 1;
}

// Whether the content at `line[i]` starts a flow collection, block scalar, comment or complex key.
private bool startsNonKey(string line, size_t i) pure nothrow @nogc
{
    switch (line[i])
    {
    case '[':
    case '{':
    case '|':
    case '>':
    case '#':
        return true;
    case '?':
        return i + 1 == line.length || line[i + 1] == ' ';
    default:
        return false;
    }
}
