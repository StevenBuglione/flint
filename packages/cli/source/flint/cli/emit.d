module flint.cli.emit;

import flint.cli.internal.metadata : CommandNode;
import flint.cli.scan : Binding, Field, missing;
import flint.cli.types : Shell;
import std.base64 : Base64;
import std.conv : to;

@safe:

private alias Sink = void delegate(scope const(char)[]) @safe;

/// Emit the fixed-width, plain-text help for a command schema.
package(flint.cli) void renderHelp(scope const CommandNode[] nodes, scope Sink write)
{
    const root = nodes[0];
    wrapped(root.name ~ (root.description.length == 0 ? "" : " - " ~ root.description), 0, write);
    write("\n");
    string usage = "Usage " ~ root.name ~ " [options]";
    foreach (ref const field; root.fields)
    {
        if (field.binding == Binding.positional)
            usage ~= " " ~ argument(field);
    }
    if (hasChildren(root.fields))
        usage ~= " [command]";
    wrapped(usage, 0, write);
    write("\nOptions\n");
    foreach (ref const field; root.fields)
    {
        if (field.binding == Binding.option)
            optionRow(field, write);
    }
    row("-h, --help", "Show help", write);
    row("--version", "Show version " ~ root.versionText, write);
    row("--completion <shell>", "Generate completion for bash, zsh, or powershell", write);

    descriptionSection(root.fields, Binding.positional, "Arguments", write);
    descriptionSection(root.fields, Binding.command, "Commands", write);
}

private bool hasChildren(scope const Field[] fields) pure nothrow @nogc
{
    foreach (ref const field; fields)
    {
        if (field.binding == Binding.command)
            return true;
    }
    return false;
}

private void descriptionSection(scope const Field[] fields, Binding kind, string title, scope Sink write)
{
    bool printed;
    foreach (ref const field; fields)
    {
        if (field.binding != kind)
            continue;
        if (!printed)
        {
            write("\n" ~ title ~ "\n");
            printed = true;
        }
        const name = kind == Binding.positional ? argument(field) : field.name;
        row(name, field.help, write);
    }
}

private string argument(scope ref const Field field)
{
    const item = field.member ~ (field.repeated ? "..." : "");
    return field.required ? "<" ~ item ~ ">" : "[" ~ item ~ "]";
}

private void optionRow(scope ref const Field field, scope Sink write)
{
    string label = field.label.idup;
    if (field.shortName != '\0')
        label = "-" ~ field.shortName ~ ", " ~ label;
    label ~= field.boolean ? ", --no-" ~ field.name : " <" ~ field.typeName ~ ">";
    if (field.repeated)
        label ~= "...";

    string help = field.help.idup;
    if (field.required)
        help ~= " (required)";
    if (field.environment.length != 0)
        help ~= " [env " ~ field.environment ~ "]";
    row(label, help, write);
}

private void row(scope const(char)[] label, scope const(char)[] explanation, scope Sink write)
{
    wrapped(label, 2, write);
    if (explanation.length != 0)
        wrapped(explanation, 4, write);
}

private bool whitespace(char value) pure nothrow @nogc
{
    return value == ' ' || value == '\t' || value == '\r' || value == '\n';
}

private void wrapped(scope const(char)[] text, size_t indent, scope Sink write)
{
    enum string spaces = "    ";
    write(spaces[0 .. indent]);
    size_t column = indent;
    while (text.length != 0)
    {
        size_t start;
        while (start < text.length && whitespace(text[start]))
            ++start;
        text = text[start .. $];
        if (text.length == 0)
            break;
        size_t word;
        while (word < text.length && !whitespace(text[word]))
            ++word;

        if (column != indent && column + 1 + word > 80)
        {
            write("\n" ~ spaces[0 .. indent]);
            column = indent;
        }
        if (column != indent)
        {
            write(" ");
            ++column;
        }
        writeLongWord(text[0 .. word], spaces[0 .. indent], column, write);
        text = text[word .. $];
    }
    write("\n");
}

private void writeLongWord(scope const(char)[] word, scope const(char)[] padding, ref size_t column, scope Sink write)
{
    while (word.length > 80 - column)
    {
        size_t part = 80 - column;
        // Back up to a UTF-8 scalar boundary before wrapping.
        while ((word[part] & 0xC0) == 0x80)
            --part;
        write(word[0 .. part]);
        write("\n");
        write(padding);
        column = padding.length;
        word = word[part .. $];
    }
    write(word);
    column += word.length;
}

/// Emit shell registration and literal completion candidates.
package(flint.cli) void renderCompletion(scope const CommandNode[] nodes, Shell shell, scope Sink write)
{
    final switch (shell)
    {
    case Shell.bash:
        bash(nodes, write);
        break;
    case Shell.zsh:
        zsh(nodes, write);
        break;
    case Shell.powershell:
        powershell(nodes, write);
        break;
    }
}

private string functionName(scope const(char)[] command)
{
    ulong hash = 0xCBF2_9CE4_8422_2325;
    foreach (byteValue; command)
        hash = (hash ^ cast(ubyte) byteValue) * 0x100_0000_01B3;
    char[16] hex;
    enum digits = "0123456789abcdef";
    foreach_reverse (ref ch; hex)
    {
        ch = digits[hash & 0xF];
        hash >>= 4;
    }
    return "_flint_cli_" ~ hex[].idup;
}

private string quotePosix(scope const(char)[] source)
{
    string result = "'";
    foreach (ch; source)
        result ~= ch == '\'' ? "'\\''" : [ch];
    return result ~ "'";
}

private string quotePs(scope const(char)[] source)
{
    // All metadata in PowerShell source is inert ASCII, including any curly quotes.
    const encoded = Base64.encode(cast(const(ubyte)[]) source).idup;
    return "([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" ~ encoded ~ "')))";
}

private void forEachCandidate(scope const Field[] fields, scope void delegate(scope const(char)[]) @safe accept)
{
    foreach (ref const field; fields)
    {
        if (field.binding == Binding.command)
        {
            accept(field.name);
            continue;
        }
        if (field.binding != Binding.option)
            continue;
        accept(field.label);
        if (field.shortName != '\0')
            accept("-" ~ field.shortName);
        if (field.boolean)
            accept("--no-" ~ field.name);
    }
    foreach (builtin; ["--help", "-h", "--version", "--completion"])
        accept(builtin);
}

private void posixTransitions(scope const CommandNode[] nodes, scope Sink write)
{
    foreach (index, ref const node; nodes)
    {
        if (node.parent != missing)
        {
            const transition = node.parent.to!string ~ ":" ~ node.name;
            write("      " ~ quotePosix(transition) ~ ") node=" ~ index.to!string ~ " ;;\n");
        }
        const prefix = index.to!string ~ ":";
        foreach (ref const field; node.fields)
        {
            if (field.binding == Binding.option && !field.boolean)
            {
                write("      " ~ quotePosix(prefix ~ field.label) ~ ") skip=1 ;;\n");
                if (field.shortName != '\0')
                    write("      " ~ quotePosix(prefix ~ "-" ~ field.shortName) ~ ") skip=1 ;;\n");
            }
        }
    }
}

private void posixChoice(scope const CommandNode[] nodes, scope Sink write)
{
    write("  case \"$node\" in\n");
    foreach (index, ref const node; nodes)
    {
        write("    " ~ index.to!string ~ ") matches=(");
        forEachCandidate(node.fields, (scope const(char)[] word) @safe {
            write(" " ~ quotePosix(word));
        });
        write(" ) ;;\n");
    }
    write("  esac\n");
}

private void bash(scope const CommandNode[] nodes, scope Sink write)
{
    const id = functionName(nodes[0].name);
    write(id ~ "() {\n");
    write("  local node=0 skip=0 i word match escaped prefix\n" ~ "  local -a matches=()\n  COMPREPLY=()\n"
            ~ "  prefix=${COMP_WORDS[COMP_CWORD]}\n" ~ "  for ((i=1; i<COMP_CWORD; ++i)); do\n"
            ~ "    word=${COMP_WORDS[i]}\n" ~ "    if ((skip)); then skip=0; continue; fi\n"
            ~ "    [[ $word == -- ]] && return 0\n" ~ "    case \"$node:$word\" in\n");
    posixTransitions(nodes, write);
    write("      *) [[ $word == -* ]] || break ;;\n    esac\n  done\n" ~ "  ((skip)) && return 0\n");
    posixChoice(nodes, write);
    write("  for match in \"${matches[@]}\"; do\n" ~ "    if [[ $match == \"$prefix\"* ]]; then\n");
    write("      printf -v escaped '%q' \"$match\"\n" ~ "      COMPREPLY+=(\"$escaped\")\n" ~ "    fi\n  done\n}\n");
    write("complete -F " ~ id ~ " -- " ~ quotePosix(nodes[0].name) ~ "\n");
}

private void zsh(scope const CommandNode[] nodes, scope Sink write)
{
    const id = functionName(nodes[0].name);
    write(id ~ "() {\n");
    write("  local state line context word\n" ~ "  local -i original_current=$CURRENT\n"
            ~ "  local -a original_words=(\"${words[@]}\") matches=()\n" ~ "  local -i node=0 skip=0 i\n"
            ~ "  _arguments '*:argument:->flint_candidates'\n" ~ "  [[ $state == flint_candidates ]] || return 0\n"
            ~ "  for ((i=2; i<original_current; ++i)); do\n" ~ "    word=${original_words[i]}\n"
            ~ "    if ((skip)); then skip=0; continue; fi\n"
            ~ "    [[ $word == -- ]] && return 0\n" ~ "    case \"$node:$word\" in\n");
    posixTransitions(nodes, write);
    write("      *) [[ $word == -* ]] || break ;;\n    esac\n  done\n" ~ "  ((skip)) && return 0\n");
    posixChoice(nodes, write);
    write("  compadd -- \"${matches[@]}\"\n}\n");
    write("compdef " ~ id ~ " " ~ quotePosix(nodes[0].name) ~ "\n");
}

private void psTransition(scope Sink write, scope const(char)[] key, string target)
{
    write("  $steps.Add(" ~ quotePs(key) ~ ", " ~ target ~ ")\n");
}

private void powershell(scope const CommandNode[] nodes, scope Sink write)
{
    write("Register-ArgumentCompleter -Native -CommandName " ~ quotePs(nodes[0].name) ~ " -ScriptBlock {\n"
            ~ "  param($wordToComplete, $commandAst, $cursorPosition)\n"
            ~ "  $steps = [Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)\n");
    foreach (index, ref const node; nodes)
    {
        if (node.parent != missing)
            psTransition(write, node.parent.to!string ~ ":" ~ node.name, index.to!string);
        const prefix = index.to!string ~ ":";
        foreach (ref const field; node.fields)
        {
            if (field.binding == Binding.option && !field.boolean)
            {
                psTransition(write, prefix ~ field.label, "-1");
                if (field.shortName != '\0')
                    psTransition(write, prefix ~ "-" ~ field.shortName, "-1");
            }
        }
    }
    write("  $node = 0\n  $skip = $false\n");
    write("  for ($i = 1; $i -lt $commandAst.CommandElements.Count; ++$i) {\n");
    write("    $argNode = $commandAst.CommandElements[$i]\n");
    write("    if ($argNode.Extent.EndOffset -ge $cursorPosition) { break }\n");
    write("    if ($skip) { $skip = $false; continue }\n");
    write("    $word = $argNode.Extent.Text\n");
    write("    if ($argNode -is [System.Management.Automation.Language.StringConstantExpressionAst]) {\n");
    write("      $word = $argNode.Value\n    }\n");
    write("    if ($word -ceq '--') { return }\n");
    write("    $nextNode = 0\n");
    write("    if ($steps.TryGetValue(($node.ToString() + ':' + $word), [ref]$nextNode)) {\n");
    write("      if ($nextNode -lt 0) { $skip = $true } else { $node = $nextNode }\n");
    write("    } elseif (!$word.StartsWith('-')) { break }\n");
    write("  }\n  if ($skip) { return }\n");
    write("  switch ($node) {\n");
    psChoice(nodes, write);
    write("  }\n  foreach ($match in $matches) {\n");
    write("    if ($match.StartsWith($wordToComplete, [StringComparison]::Ordinal)) {\n");
    write("      $left = [string][char]0x2018\n      $right = [string][char]0x2019\n");
    write("      $escaped = $match.Replace(\"'\", \"''\").Replace($left, $left + $left)"
            ~ ".Replace($right, $right + $right)\n");
    write("      $literal = \"'\" + $escaped + \"'\"\n");
    write("      [System.Management.Automation.CompletionResult]::new($literal, $match, 'ParameterValue', $match)\n");
    write("    }\n  }\n}\n");
}

private void psChoice(scope const CommandNode[] nodes, scope Sink write)
{
    foreach (index, ref const node; nodes)
    {
        write("    " ~ index.to!string ~ " { $matches = @(\n");
        forEachCandidate(node.fields, (scope const(char)[] word) @safe {
            write("      " ~ quotePs(word) ~ "\n");
        });
        write("    ) }\n");
    }
}
