/// Derived queries: Spring Data's `PartTree` method-name grammar, translated to SQL at build time
/// (docs/spring/aot-contract.md section 8).
module flint_tool.engine.aot.query;

@safe:

/// The result shape of a derived query (`flint.engine.aot.query.QueryKind`).
enum QueryKind
{
    list,
    single,
    optional,
    count,
    exists,
    delete_,
    stream
}

/// One property of the domain type, as the query sees it.
struct Column
{
    /// D field name.
    string property;
    /// Column name.
    string column;
    /// Whether the field is itself a struct or class (a nested path).
    bool nested;
}

/// The domain type.
struct Domain
{
    /// Fully qualified D name.
    string type;
    /// Simple name, for messages.
    string name;
    /// Table name.
    string table;
    /// Persistent properties in declaration order.
    Column[] columns;
}

/// A translated query.
struct DerivedQuery
{
    /// The method.
    string method;
    /// SQL with `?` placeholders.
    string sql;
    /// The method parameter feeding each placeholder.
    string[] parameters;
    /// Per placeholder: "", "starting", "ending" or "containing".
    string[] likeTransforms;
    /// Result shape.
    QueryKind kind;
    /// First/Top N, 0 when absent.
    int limit;
}

/// Why a method name did not translate: FLINT-E1101, or E1114 for a nested path.
struct QueryError
{
    /// Diagnostic code.
    string code;
    /// Message, worded as Spring Data's.
    string message;
}

/// Spring Data Relational's default table or column name: snake case, lower case.
string snakeCase(string name)
{
    import std.ascii : isUpper, toLower;

    string result;
    foreach (index, ch; name)
    {
        if (isUpper(ch) && index > 0 && !isUpper(name[index - 1]))
            result ~= '_';
        else if (isUpper(ch) && index > 0 && index + 1 < name.length && !isUpper(name[index + 1])
                && name[index + 1] != '_')
            result ~= '_';
        result ~= toLower(ch);
    }
    return result;
}

private immutable string[] subjects = [
    "find", "read", "get", "query", "search", "stream", "count", "exists", "delete", "remove"
];

/// Operators longest first, with the number of parameters each consumes.
private struct Operator
{
    string keyword;
    string sql;
    int arguments;
    string like;
}

private immutable Operator[] operators = [
    Operator("IsNotNull", "IS NOT NULL", 0), Operator("NotNull", "IS NOT NULL", 0),
    Operator("IsNull", "IS NULL", 0), Operator("Null", "IS NULL", 0),
    Operator("IsLessThanEqual", "<=", 1), Operator("LessThanEqual", "<=", 1),
    Operator("IsLessThan", "<", 1), Operator("LessThan", "<", 1),
    Operator("IsGreaterThanEqual", ">=", 1), Operator("GreaterThanEqual", ">=", 1),
    Operator("IsGreaterThan", ">", 1), Operator("GreaterThan", ">", 1), Operator("IsBefore", "<",
            1), Operator("Before", "<", 1), Operator("IsAfter", ">", 1), Operator("After", ">", 1),
    Operator("IsBetween", "BETWEEN", 2), Operator("Between", "BETWEEN", 2),
    Operator("IsNotLike", "NOT LIKE", 1), Operator("NotLike", "NOT LIKE", 1),
    Operator("IsLike", "LIKE", 1), Operator("Like", "LIKE", 1),
    Operator("IsStartingWith", "LIKE", 1, "starting"), Operator("StartingWith", "LIKE", 1,
            "starting"), Operator("StartsWith", "LIKE", 1, "starting"),
    Operator("IsEndingWith", "LIKE", 1, "ending"), Operator("EndingWith", "LIKE", 1, "ending"),
    Operator("EndsWith", "LIKE", 1, "ending"),
    Operator("IsNotContaining", "NOT LIKE", 1, "containing"),
    Operator("NotContaining", "NOT LIKE", 1, "containing"),
    Operator("IsContaining", "LIKE", 1, "containing"), Operator("Containing", "LIKE", 1,
            "containing"), Operator("Contains", "LIKE", 1, "containing"),
    Operator("IsNotIn", "NOT IN", 1), Operator("NotIn", "NOT IN", 1), Operator("IsIn", "IN", 1),
    Operator("In", "IN", 1), Operator("IsTrue", "= TRUE", 0), Operator("True", "= TRUE", 0),
    Operator("IsFalse", "= FALSE", 0), Operator("False", "= FALSE", 0), Operator("IsNot", "<>", 1),
    Operator("Not", "<>", 1), Operator("Is", "=", 1), Operator("Equals", "=", 1)
];

/// Split `text` at every `word` that has text before it and an upper-case letter after it (Spring Data splits on
/// `Or(?=\p{Lu})` and `And(?=\p{Lu})`).
private string[] splitKeyword(string text, string word)
{
    import std.ascii : isUpper;

    string[] parts;
    size_t start;
    for (size_t index = 1; index + word.length < text.length; ++index)
    {
        if (index > start && text[index .. index + word.length] == word && isUpper(text[index + word.length]))
        {
            parts ~= text[start .. index];
            start = index + word.length;
            index = start;
        }
    }
    parts ~= text[start .. $];
    return parts;
}

private string decapitalize(string name)
{
    import std.ascii : toLower;

    return name.length ? toLower(name[0]) ~ name[1 .. $] : name;
}

private bool endsWith(string text, string suffix)
{
    return text.length >= suffix.length && text[$ - suffix.length .. $] == suffix;
}

/// The subject (prefix and modifiers) and the predicate after `By`.
private bool splitSubject(string method, out string subject, out string modifiers, out string predicate)
{
    import std.string : indexOf;

    foreach (candidate; subjects)
    {
        if (method.length < candidate.length || method[0 .. candidate.length] != candidate)
            continue;
        subject = candidate;
        const rest = method[candidate.length .. $];
        const by = rest.indexOf("By");
        if (by < 0)
        {
            modifiers = rest;
            return true;
        }
        modifiers = rest[0 .. by];
        predicate = rest[by + 2 .. $];
        return true;
    }
    return false;
}

private int limitOf(string modifiers)
{
    import std.ascii : isDigit;
    import std.conv : to;
    import std.string : indexOf;

    foreach (word; ["First", "Top"])
    {
        const at = modifiers.indexOf(word);
        if (at < 0)
            continue;
        size_t end = at + word.length;
        while (end < modifiers.length && isDigit(modifiers[end]))
            ++end;
        return end > at + word.length ? modifiers[at + word.length .. end].to!int : 1;
    }
    return 0;
}

private const(Column)* findColumn(return ref const Domain domain, string property)
{
    foreach (ref column; domain.columns)
    {
        if (column.property == property)
            return &column;
    }
    return null;
}

/// A property path that is not a direct property but starts with a nested one.
private bool nestedPath(const ref Domain domain, string property)
{
    foreach (ref column; domain.columns)
    {
        if (column.nested && property.length > column.property.length
                && property[0 .. column.property.length] == column.property)
            return true;
    }
    return false;
}

/// Translate one part ("LastNameIgnoreCase") into SQL, consuming parameters.
private bool translatePart(string part, bool allIgnoreCase, const ref Domain domain,
        scope const string[] parameters, ref size_t used, ref DerivedQuery query, out string sql, out QueryError error)
{
    bool ignoreCase = allIgnoreCase;
    foreach (suffix; ["IgnoringCase", "IgnoreCase"])
    {
        if (part.endsWith(suffix))
        {
            part = part[0 .. $ - suffix.length];
            ignoreCase = true;
            break;
        }
    }
    Operator operator = Operator("", "=", 1);
    foreach (ref candidate; operators)
    {
        if (part.endsWith(candidate.keyword) && part.length > candidate.keyword.length)
        {
            operator = candidate;
            part = part[0 .. $ - candidate.keyword.length];
            break;
        }
    }
    const property = decapitalize(part);
    const column = findColumn(domain, property);
    if (column is null)
    {
        error = nestedPath(domain, property) ? QueryError("FLINT-E1114",
                "nested property path `" ~ property ~ "` of " ~ domain.name ~ " needs Data JDBC's joins") : QueryError(
                "FLINT-E1101", "No property '" ~ property ~ "' found for type '" ~ domain.name ~ "'");
        return false;
    }
    if (used + operator.arguments > parameters.length)
    {
        error = QueryError("FLINT-E1101", "method " ~ query.method ~ " needs more parameters than it declares");
        return false;
    }
    string left = column.column;
    string placeholder = "?";
    if (ignoreCase)
    {
        left = "UPPER(" ~ left ~ ")";
        placeholder = "UPPER(?)";
    }
    if (operator.arguments == 0)
        sql = left ~ " " ~ operator.sql;
    else if (operator.arguments == 2)
        sql = left ~ " BETWEEN " ~ placeholder ~ " AND " ~ placeholder;
    else if (operator.sql == "IN" || operator.sql == "NOT IN")
        sql = left ~ " " ~ operator.sql ~ " (" ~ placeholder ~ ")";
    else
        sql = left ~ " " ~ operator.sql ~ " " ~ placeholder;
    foreach (argument; 0 .. operator.arguments)
    {
        query.parameters ~= parameters[used++];
        query.likeTransforms ~= operator.like;
    }
    return true;
}

/// `OrderBy` terms: `LastNameDescFirstNameAsc`, or a single property without a direction.
private bool translateOrder(string order, const ref Domain domain, out string sql, out QueryError error)
{
    import std.array : join;
    import std.ascii : isUpper;

    string[] terms;
    size_t start;
    size_t index;
    while (start < order.length)
    {
        string direction;
        size_t end = order.length;
        for (index = start + 1; index < order.length; ++index)
        {
            foreach (word; ["Desc", "Asc"])
            {
                const after = index + word.length;
                if (direction.length == 0 && after <= order.length && order[index .. after] == word
                        && (after == order.length || isUpper(order[after])))
                {
                    direction = word;
                    end = index;
                }
            }
            if (direction.length)
                break;
        }
        const property = decapitalize(order[start .. end]);
        const column = findColumn(domain, property);
        if (column is null)
        {
            error = QueryError("FLINT-E1101", "No property '" ~ property ~ "' found for type '" ~ domain.name ~ "'");
            return false;
        }
        terms ~= column.column ~ (direction == "Desc" ? " DESC" : " ASC");
        start = end + direction.length;
    }
    sql = terms.join(", ");
    return true;
}

private QueryKind kindOf(string subject, string returnType)
{
    import std.algorithm.searching : canFind, startsWith;

    if (subject == "count")
        return QueryKind.count;
    if (subject == "exists")
        return QueryKind.exists;
    if (subject == "delete" || subject == "remove")
        return QueryKind.delete_;
    if (subject == "stream")
        return QueryKind.stream;
    if (returnType.endsWith("[]") || returnType.canFind("List!("))
        return QueryKind.list;
    if (returnType.startsWith("flint.java.util.Optional!(") || returnType.canFind(".Nullable!("))
        return QueryKind.optional;
    return QueryKind.single;
}

/// Translate a repository method into a derived query.
bool deriveQuery(string method, string returnType, scope const string[] parameters,
        const ref Domain domain, out DerivedQuery query, out QueryError error)
{
    import std.array : join;
    import std.string : indexOf;

    query.method = method;
    string subject;
    string modifiers;
    string predicate;
    if (!splitSubject(method, subject, modifiers, predicate))
    {
        error = QueryError("FLINT-E1101", "method " ~ method ~ " does not start with a query subject (find, read, "
                ~ "get, query, search, stream, count, exists, delete or remove)");
        return false;
    }
    query.kind = kindOf(subject, returnType);
    query.limit = limitOf(modifiers);
    string order;
    const orderAt = predicate.indexOf("OrderBy");
    if (orderAt >= 0)
    {
        order = predicate[orderAt + "OrderBy".length .. $];
        predicate = predicate[0 .. orderAt];
    }
    bool allIgnoreCase;
    foreach (suffix; ["AllIgnoringCase", "AllIgnoreCase"])
    {
        if (predicate.endsWith(suffix))
        {
            predicate = predicate[0 .. $ - suffix.length];
            allIgnoreCase = true;
        }
    }
    string[] disjunctions;
    size_t used;
    if (predicate.length)
    {
        foreach (orPart; splitKeyword(predicate, "Or"))
        {
            string[] conjunctions;
            foreach (andPart; splitKeyword(orPart, "And"))
            {
                string sql;
                if (!translatePart(andPart, allIgnoreCase, domain, parameters, used, query, sql, error))
                    return false;
                conjunctions ~= sql;
            }
            disjunctions ~= conjunctions.join(" AND ");
        }
    }
    if (used != parameters.length)
    {
        error = QueryError("FLINT-E1101",
                "method " ~ method ~ " declares " ~ count(
                    parameters.length) ~ " parameters but its name binds " ~ count(used));
        return false;
    }
    string orderSql;
    if (order.length && !translateOrder(order, domain, orderSql, error))
        return false;
    query.sql = render(query.kind, modifiers, domain, disjunctions, orderSql, query.limit);
    return true;
}

private string count(size_t value)
{
    import std.conv : to;

    return value.to!string;
}

private string render(QueryKind kind, string modifiers, const ref Domain domain,
        scope const string[] disjunctions, string orderSql, int limit)
{
    import std.array : join;
    import std.conv : to;
    import std.string : indexOf;

    string where;
    if (disjunctions.length == 1)
        where = " WHERE " ~ disjunctions[0];
    else if (disjunctions.length > 1)
        where = " WHERE (" ~ disjunctions.join(") OR (") ~ ")";
    if (kind == QueryKind.count)
        return "SELECT COUNT(*) FROM " ~ domain.table ~ where;
    if (kind == QueryKind.exists)
        return "SELECT 1 FROM " ~ domain.table ~ where ~ " LIMIT 1";
    if (kind == QueryKind.delete_)
        return "DELETE FROM " ~ domain.table ~ where;
    string[] columns;
    foreach (ref column; domain.columns)
        columns ~= column.column;
    string sql = "SELECT " ~ (modifiers.indexOf("Distinct") >= 0
            ? "DISTINCT " : "") ~ columns.join(", ") ~ " FROM " ~ domain.table ~ where;
    if (orderSql.length)
        sql ~= " ORDER BY " ~ orderSql;
    if (limit > 0)
        sql ~= " LIMIT " ~ limit.to!string;
    return sql;
}
