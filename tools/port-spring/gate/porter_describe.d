/++
The porter gate's API description of a declaration (docs/spring/phase2/porter-plan.md, gate (b)).

`tools/porter_gate.py` compiles a probe that prints `describe!(symbol)` with `pragma(msg)` once against the hand
port and once against the tree with the generated declaration spliced in, on DMD and LDC, and compares the text.
The text covers what a caller can observe: the kind, visibility, attributes and UDAs, base types, every member's
type with its parameter defaults as written, function attributes, field initializers and enum values. It is a tool, not framework
code, so it may use reflection freely.
+/
module porter_describe;

import std.format : format;
import std.traits : BaseClassesTuple, BaseTypeTuple, isFunction;

/// One line per observable property, members sorted by name so declaration order inside a type doesn't matter.
string describe(alias symbol)()
{
    return describeSymbol!symbol(__traits(identifier, symbol));
}

private string describeSymbol(alias symbol)(string path)
{
    string text = path ~ " visibility " ~ __traits(getVisibility, symbol) ~ "\n";
    static if (__traits(isDeprecated, symbol))
        text ~= path ~ " deprecated\n";
    static foreach (attribute; __traits(getAttributes, symbol))
        text ~= path ~ " uda " ~ attributeText!attribute ~ "\n";
    static if (is(symbol == enum))
    {
        text ~= path ~ " enum " ~ __traits(fullyQualifiedName, OriginalBase!symbol) ~ "\n";
        static foreach (name; __traits(allMembers, symbol))
            text ~= path ~ "." ~ name ~ " = " ~ valueText(cast(OriginalBase!symbol) __traits(getMember, symbol, name))
                ~ "\n";
    }
    else static if (is(symbol == struct) || is(symbol == union) || is(symbol == class) || is(symbol == interface))
    {
        static if (is(symbol == struct))
            text ~= path ~ " struct\n";
        else static if (is(symbol == union))
            text ~= path ~ " union\n";
        else static if (is(symbol == interface))
            text ~= path ~ " interface\n";
        else
        {
            text ~= path ~ " class" ~ (__traits(isFinalClass, symbol) ? " final" : "")
                ~ (__traits(isAbstractClass, symbol) ? " abstract" : "") ~ "\n";
            static foreach (base; BaseClassesTuple!symbol)
                text ~= path ~ " base " ~ __traits(fullyQualifiedName, base) ~ "\n";
        }
        static if (is(symbol == class) || is(symbol == interface))
            static foreach (base; BaseTypeTuple!symbol)
                static if (is(base == interface))
                    text ~= path ~ " implements " ~ __traits(fullyQualifiedName, base) ~ "\n";
        text ~= membersText!symbol(path);
    }
    else static if (isFunction!symbol)
        text ~= overloadsText!(__traits(parent, symbol), __traits(identifier, symbol))(path);
    else
        text ~= path ~ " value " ~ typeof(symbol).stringof ~ " = " ~ valueText(symbol) ~ "\n";
    return text;
}

private template OriginalBase(alias symbol)
{
    static if (is(symbol Base == enum))
        alias OriginalBase = Base;
}

private string membersText(alias aggregate)(string path)
{
    import std.algorithm.sorting : sort;

    string[] lines;
    static foreach (name; __traits(derivedMembers, aggregate))
    {
        static if (!isImplicit(name))
            lines ~= memberText!(aggregate, name)(path ~ "." ~ name);
    }
    sort(lines);
    string text;
    foreach (line; lines)
        text ~= line;
    return text;
}

private bool isImplicit(string name)
{
    import std.algorithm.searching : startsWith;

    // Compiler-generated members (__xtoHash, __xopEquals, __fieldPostblit ...) follow from the declared ones.
    return name.startsWith("__") && name != "__ctor" && name != "__dtor";
}

private string memberText(alias aggregate, string name)(string path)
{
    static if (is(typeof(__traits(getOverloads, aggregate, name))) && __traits(getOverloads, aggregate, name).length)
        return overloadsText!(aggregate, name)(path);
    else static if (is(__traits(getMember, aggregate, name)))
        return describeSymbol!(__traits(getMember, aggregate, name))(path);
    else static if (__traits(compiles, __traits(getMember, aggregate, name).offsetof))
        return fieldText!(aggregate, name)(path);
    else static if (__traits(compiles, valueText(__traits(getMember, aggregate, name))))
        return path ~ " " ~ storageText!(aggregate, name) ~ typeof(__traits(getMember, aggregate, name)).stringof
            ~ " = " ~ valueText(__traits(getMember, aggregate, name)) ~ "\n";
    else
        return path ~ " " ~ storageText!(aggregate, name) ~ "symbol\n";
}

private string storageText(alias aggregate, string name)()
{
    string text = __traits(getVisibility, __traits(getMember, aggregate, name)) ~ " ";
    static if (__traits(isDeprecated, __traits(getMember, aggregate, name)))
        text ~= "deprecated ";
    static foreach (attribute; __traits(getAttributes, __traits(getMember, aggregate, name)))
        text ~= "@" ~ attributeText!attribute ~ " ";
    return text;
}

private string fieldText(alias aggregate, string name)(string path)
{
    string text = path ~ " " ~ storageText!(aggregate, name) ~ "field "
        ~ typeof(__traits(getMember, aggregate, name)).stringof;
    static if (is(aggregate == struct) || is(aggregate == union))
    {
        static if (__traits(compiles, { enum value = valueText(__traits(getMember, aggregate.init, name)); }))
            text ~= " = " ~ valueText(__traits(getMember, aggregate.init, name));
        else
            text ~= " = <opaque>";
    }
    return text ~ "\n";
}

private string overloadsText(alias parent, string name)(string path)
{
    string text;
    static foreach (index, overload; __traits(getOverloads, parent, name))
    {
        text ~= format("%s#%s %s%s", path, index, storageText!(parent, name), typeof(overload).stringof);
        static foreach (attribute; __traits(getFunctionAttributes, overload))
            text ~= " " ~ attribute;
        static if (__traits(isStaticFunction, overload))
            text ~= " static";
        static if (__traits(isVirtualMethod, overload))
            text ~= " virtual";
        static if (__traits(isFinalFunction, overload))
            text ~= " final";
        static if (__traits(isAbstractFunction, overload))
            text ~= " abstract";
        static if (__traits(isDeprecated, overload))
            text ~= " deprecated";
        text ~= "\n";
    }
    return text;
}

private string attributeText(alias attribute)()
{
    static if (is(attribute))
        return "type " ~ attribute.stringof;
    else static if (__traits(compiles, valueText(attribute)))
        return typeof(attribute).stringof ~ " " ~ valueText(attribute);
    else
        return attribute.stringof;
}

private string valueText(T)(T value)
{
    static if (is(T == class) || is(T == interface))
        return value is null ? "null" : "<object>";
    else static if (is(T : const(char)[]))
        return value is null ? "null" : format("%(%s%)", [value]);
    else static if (__traits(compiles, format("%s", value)))
        return format("%s", value);
    else
        return "<opaque>";
}
