/// Conditions compiled to D (docs/spring/aot-contract.md section 5.5).
///
/// Class presence is decided here, at build time. Everything else becomes a boolean D expression over the
/// runtime's `ConditionContext c`, evaluated at startup.
module flint_tool.engine.aot.conditions;

import flint_tool.engine.aot.merge : MergedSet;

@safe:

/// The outcome of a definition's conditions.
struct ConditionOutcome
{
    /// False when a build-time condition removed the definition.
    bool included = true;
    /// Why it was removed, for `--verbose` output.
    string reason;
    /// Startup terms, to be joined with `&&`.
    string[] terms;
    /// Class names whose presence is still unknown.
    string[] unknownClasses;
    /// Messages for FLINT-E1102 and FLINT-E1107.
    string[] errors;
    /// The codes of `errors`, parallel.
    string[] codes;
}

/// A D string literal.
string literal(string text)
{
    import std.format : format;

    string result = "\"";
    foreach (char ch; text)
    {
        switch (ch)
        {
        case '"':
            result ~= "\\\"";
            break;
        case '\\':
            result ~= "\\\\";
            break;
        case '\n':
            result ~= "\\n";
            break;
        case '\t':
            result ~= "\\t";
            break;
        case '\r':
            result ~= "\\r";
            break;
        default:
            if (ch < 0x20)
                result ~= format!"\\x%02X"(ch);
            else
                result ~= ch;
        }
    }
    return result ~ "\"";
}

/// Compile one Spring profile expression (`prod & !cloud`, `(a | b) & c`) to D. False on a malformed one.
bool compileProfile(string expression, out string code, out string error)
{
    auto parser = ProfileParser(expression);
    code = parser.parseExpression();
    parser.skipSpace();
    if (parser.error.length == 0 && parser.position < expression.length)
        parser.error = "unexpected `" ~ expression[parser.position .. $] ~ "`";
    if (parser.error.length || code.length == 0)
    {
        error = "malformed @Profile expression \"" ~ expression ~ "\": " ~ (parser.error.length
                ? parser.error : "it is empty");
        return false;
    }
    return true;
}

private struct ProfileParser
{
    string text;
    size_t position;
    string error;

    void skipSpace()
    {
        while (position < text.length && text[position] == ' ')
            ++position;
    }

    // Spring forbids mixing & and | without parentheses.
    string parseExpression()
    {
        string left = parseUnary();
        string operator;
        while (error.length == 0)
        {
            skipSpace();
            if (position >= text.length || (text[position] != '&' && text[position] != '|'))
                break;
            const current = text[position] == '&' ? "&&" : "||";
            if (operator.length && operator != current)
            {
                error = "mixed '&' and '|' without parentheses";
                break;
            }
            operator = current;
            ++position;
            left = left ~ " " ~ current ~ " " ~ parseUnary();
        }
        return operator.length ? "(" ~ left ~ ")" : left;
    }

    string parseUnary()
    {
        skipSpace();
        if (position >= text.length)
        {
            error = "an operand is missing";
            return null;
        }
        if (text[position] == '!')
        {
            ++position;
            return "!" ~ parseUnary();
        }
        if (text[position] == '(')
        {
            ++position;
            const inner = parseExpression();
            skipSpace();
            if (position >= text.length || text[position] != ')')
            {
                error = "a ')' is missing";
                return null;
            }
            ++position;
            return inner;
        }
        const start = position;
        while (position < text.length && text[position] != ' ' && text[position] != '&'
                && text[position] != '|' && text[position] != '(' && text[position] != ')' && text[position] != '!')
            ++position;
        if (position == start)
        {
            error = "an operand is missing";
            return null;
        }
        return "c.acceptsProfile(" ~ literal(text[start .. position]) ~ ")";
    }
}

/// Class names of `@ConditionalOnClass(name)`, `@ConditionalOnClass(value)` and `@ConditionalOnMissingClass`.
private string[] classNames(const ref MergedSet merged, string type, string[] attributes)
{
    string[] names;
    if (const annotation = merged.get(type))
    {
        foreach (attribute; attributes)
            names ~= annotation.get(attribute).strings;
    }
    return names;
}

/// Evaluate the conditions on one element. `beanType` is what an attribute-less `@ConditionalOnBean` means.
ConditionOutcome evaluate(const ref MergedSet merged, string beanType, const bool[string] present)
{
    import flint_tool.engine.aot.names : onClass, onMissingClass;

    ConditionOutcome outcome;
    foreach (name; classNames(merged, onClass, ["value", "name"]))
        decideClass(name, true, present, outcome);
    foreach (name; classNames(merged, onMissingClass, ["value"]))
        decideClass(name, false, present, outcome);
    profileTerms(merged, outcome);
    propertyTerms(merged, outcome);
    beanTerms(merged, beanType, outcome);
    return outcome;
}

private void decideClass(string name, bool wanted, const bool[string] present, ref ConditionOutcome outcome)
{
    const answer = name in present;
    if (answer is null)
    {
        outcome.unknownClasses ~= name;
        return;
    }
    if (*answer != wanted && outcome.included)
    {
        outcome.included = false;
        outcome.reason = wanted ? "@ConditionalOnClass: " ~ name
            ~ " is not in the closure" : "@ConditionalOnMissingClass: " ~ name ~ " is in the closure";
    }
}

private void profileTerms(const ref MergedSet merged, ref ConditionOutcome outcome)
{
    import std.array : join;
    import flint_tool.engine.aot.names : profile;

    const annotation = merged.get(profile);
    if (annotation is null)
        return;
    string[] alternatives;
    foreach (expression; annotation.get("value").strings)
    {
        string code;
        string error;
        if (compileProfile(expression, code, error))
            alternatives ~= code;
        else
        {
            outcome.errors ~= error;
            outcome.codes ~= "FLINT-E1102";
        }
    }
    if (alternatives.length == 1)
        outcome.terms ~= alternatives[0];
    else if (alternatives.length > 1)
        outcome.terms ~= "(" ~ alternatives.join(" || ") ~ ")";
}

private void propertyTerms(const ref MergedSet merged, ref ConditionOutcome outcome)
{
    import flint_tool.engine.aot.names : onBooleanProperty, onConfig, onProperty;

    if (const annotation = merged.get(onProperty))
    {
        string prefix = annotation.text("prefix");
        if (prefix.length && prefix[$ - 1] != '.')
            prefix ~= ".";
        auto names = annotation.get("name").strings;
        if (names.length == 0)
            names = annotation.get("value").strings;
        foreach (name; names)
            outcome.terms ~= "c.property(" ~ literal(prefix ~ name) ~ ", " ~ literal(
                    annotation.text("havingValue")) ~ ", " ~ (annotation.flag("matchIfMissing") ? "true" : "false")
                ~ ")";
    }
    if (const annotation = merged.get(onBooleanProperty))
    {
        string prefix = annotation.text("prefix");
        if (prefix.length && prefix[$ - 1] != '.')
            prefix ~= ".";
        auto names = annotation.get("name").strings;
        if (names.length == 0)
            names = annotation.get("value").strings;
        foreach (name; names)
            outcome.terms ~= "c.property(" ~ literal(prefix ~ name) ~ ", " ~ (annotation.flag("havingValue",
                    true) ? "\"true\"" : "\"false\"") ~ ", " ~ (annotation.flag("matchIfMissing") ? "true" : "false")
                ~ ")";
    }
    if (const annotation = merged.get(onConfig))
        outcome.terms ~= "c.property(" ~ literal(annotation.text("section")) ~ ", \"\", false)";
}

private void beanTerms(const ref MergedSet merged, string beanType, ref ConditionOutcome outcome)
{
    import flint_tool.engine.aot.names : onBean, onMissingBean, onNotWebApplication,
        onSingleCandidate, onWebApplication;

    foreach (type; [onBean, onMissingBean])
    {
        const annotation = merged.get(type);
        if (annotation is null)
            continue;
        const negate = type == onMissingBean ? "!" : "";
        auto types = annotation.get("value").strings ~ annotation.get("type").strings;
        const names = annotation.get("name").strings;
        if (types.length == 0 && names.length == 0)
            types = [beanType];
        foreach (name; types)
            outcome.terms ~= negate ~ "c.hasBeanOfType(" ~ literal(name) ~ ")";
        foreach (name; names)
            outcome.terms ~= negate ~ "c.hasBeanNamed(" ~ literal(name) ~ ")";
    }
    if (const annotation = merged.get(onSingleCandidate))
    {
        auto types = annotation.get("value").strings ~ annotation.get("type").strings;
        if (types.length == 0)
            types = [beanType];
        foreach (name; types)
            outcome.terms ~= "c.hasSingleCandidate(" ~ literal(name) ~ ")";
    }
    if (const annotation = merged.get(onWebApplication))
    {
        const kind = annotation.get("type");
        outcome.terms ~= "c.isWebApplication(" ~ literal(kind.text.length ? kind.text : "SERVLET") ~ ")";
    }
    if (merged.has(onNotWebApplication))
        outcome.terms ~= "!c.isWebApplication(\"ANY\")";
}
