// SPDX-License-Identifier: Apache-2.0
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tree_sitter/api.h>

const TSLanguage *tree_sitter_java(void);

typedef struct {
    const char *bytes;
    size_t length;
} Slice;

typedef struct {
    char *bytes;
    size_t length;
    size_t capacity;
    bool failed;
} Text;

typedef struct {
    Slice name;
    Text symbol;
    TSNode node;
    Slice enum_type;
    TSNode enum_default;
    size_t offset;
    bool array;
} Field;

typedef struct {
    const char *source;
    const char *path;
    TSNode root;
    Slice package;
    TSNode declaration;
    bool is_enum;
    bool inherited;
    bool class_ref;
} JavaFile;

typedef struct {
    const char *java;
    const char *d;
} Type;

static Slice literal(const char *bytes)
{
    return (Slice){bytes, strlen(bytes)};
}

static bool equal(Slice a, Slice b)
{
    return a.length == b.length && (!a.length || !memcmp(a.bytes, b.bytes, a.length));
}

static bool is(Slice a, const char *b)
{
    return equal(a, literal(b));
}

static Slice node_text(const JavaFile *java, TSNode node)
{
    if (ts_node_is_null(node))
        return (Slice){0};
    uint32_t start = ts_node_start_byte(node);
    return (Slice){java->source + start, ts_node_end_byte(node) - start};
}

static bool kind(TSNode node, const char *name)
{
    return !ts_node_is_null(node) && !strcmp(ts_node_type(node), name);
}

static TSNode member(TSNode node, const char *name)
{
    return ts_node_child_by_field_name(node, name, (uint32_t)strlen(name));
}

static TSNode child_of_kind(TSNode node, const char *name)
{
    if (ts_node_is_null(node))
        return (TSNode){0};
    for (uint32_t index = 0; index < ts_node_child_count(node); ++index) {
        TSNode child = ts_node_child(node, index);
        if (kind(child, name))
            return child;
    }
    return (TSNode){0};
}

static bool append(Text *text, Slice value)
{
    if (text->failed || value.length > SIZE_MAX - text->length) {
        text->failed = true;
        return false;
    }
    size_t needed = text->length + value.length;
    if (needed > text->capacity) {
        size_t capacity = text->capacity ? text->capacity : 256;
        if (capacity <= SIZE_MAX / 2)
            capacity *= 2;
        if (capacity < needed)
            capacity = needed;
        char *bytes = realloc(text->bytes, capacity);
        if (!bytes) {
            text->failed = true;
            return false;
        }
        text->bytes = bytes;
        text->capacity = capacity;
    }
    if (value.length)
        memcpy(text->bytes + text->length, value.bytes, value.length);
    text->length = needed;
    return true;
}

static void add(Text *text, const char *value)
{
    append(text, literal(value));
}

static Slice contents(const Text *text)
{
    return (Slice){text->bytes, text->length};
}

static bool letter(char byte)
{
    return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte == '_';
}

static bool digit(char byte)
{
    return byte >= '0' && byte <= '9';
}

static bool identifier(Slice name)
{
    if (!name.length || !letter(name.bytes[0]))
        return false;
    for (size_t index = 1; index < name.length; ++index) {
        if (!letter(name.bytes[index]) && !digit(name.bytes[index]))
            return false;
    }
    return true;
}

static bool qualified_identifier(Slice name)
{
    if (!name.length)
        return false;
    size_t start = 0;
    for (size_t index = 0; index <= name.length; ++index) {
        if (index < name.length && name.bytes[index] != '.')
            continue;
        if (!identifier((Slice){name.bytes + start, index - start}))
            return false;
        start = index + 1;
    }
    return true;
}

static bool d_keyword(Slice name)
{
    static const char *const keywords[] = {
        "abstract", "alias", "align", "asm", "assert", "auto", "body", "bool",
        "break", "byte", "case", "cast", "catch", "cdouble", "cent", "cfloat",
        "char", "class", "const", "continue", "creal", "dchar", "debug", "default",
        "delegate", "delete", "deprecated", "do", "double", "else", "enum", "export",
        "extern", "false", "final", "finally", "float", "for", "foreach",
        "foreach_reverse", "function", "goto", "idouble", "if", "ifloat", "immutable",
        "import", "in", "inout", "int", "interface", "invariant", "ireal", "is",
        "lazy", "long", "macro", "mixin", "module", "new", "nothrow", "null",
        "out", "override", "package", "pragma", "private", "protected", "public", "pure",
        "real", "ref", "return", "scope", "shared", "short", "static", "struct",
        "super", "switch", "synchronized", "template", "this", "throw", "true", "try",
        "typeid", "typeof", "ubyte", "ucent", "uint", "ulong", "union", "unittest",
        "ushort", "version", "void", "volatile", "wchar", "while", "with",
    };
    if (name.length >= 2 && name.bytes[0] == '_' && name.bytes[1] == '_')
        return true;
    for (size_t index = 0; index < sizeof keywords / sizeof *keywords; ++index) {
        if (is(name, keywords[index]))
            return true;
    }
    return false;
}

static bool lower_name(Slice name, Text *symbol)
{
    if (!identifier(name))
        return false;
    for (size_t index = 0; index < name.length;) {
        if (name.length - index >= 6 && !memcmp(name.bytes + index, "Spring", 6)) {
            add(symbol, "Flint");
            index += 6;
        } else {
            append(symbol, (Slice){name.bytes + index, 1});
            ++index;
        }
    }
    if (d_keyword(contents(symbol)))
        add(symbol, "_");
    return !symbol->failed;
}

static int diagnostic(const JavaFile *java, TSNode node, const char *message)
{
    TSPoint start = ts_node_is_null(node) ? (TSPoint){0} : ts_node_start_point(node);
    fprintf(stderr, "%s:%" PRIu32 ":%" PRIu32 ": %s\n",
            java->path, start.row + 1, start.column + 1, message);
    return 2;
}

static bool package_and_declaration(JavaFile *java)
{
    for (uint32_t index = 0; index < ts_node_named_child_count(java->root); ++index) {
        TSNode child = ts_node_named_child(java->root, index);
        if (ts_node_is_extra(child) || kind(child, "import_declaration"))
            continue;
        if (kind(child, "package_declaration") && !java->package.length) {
            if (ts_node_named_child_count(child) != 1)
                return false;
            java->package = node_text(java, ts_node_named_child(child, 0));
        } else if (ts_node_is_null(java->declaration) &&
                   (kind(child, "annotation_type_declaration") || kind(child, "enum_declaration"))) {
            java->declaration = child;
            java->is_enum = kind(child, "enum_declaration");
        } else {
            return false;
        }
    }
    return java->package.length && qualified_identifier(java->package)
        && !ts_node_is_null(child_of_kind(child_of_kind(java->declaration, "modifiers"), "public"));
}

static Slice import_path(const JavaFile *annotation, TSNode node)
{
    TSNode path = child_of_kind(node, "scoped_identifier");
    if (ts_node_is_null(path))
        path = child_of_kind(node, "identifier");
    return node_text(annotation, path);
}

static Slice last_name(Slice name)
{
    for (size_t index = name.length; index > 0; --index) {
        if (name.bytes[index - 1] == '.')
            return (Slice){name.bytes + index, name.length - index};
    }
    return name;
}

static bool resolves(const JavaFile *annotation, Slice spelling, const char *qualified,
                     bool implicit_java_lang)
{
    Slice target = literal(qualified);
    if (equal(spelling, target))
        return true;
    if (!equal(last_name(target), spelling))
        return false;
    bool ambiguous = false;
    for (uint32_t index = 0; index < ts_node_named_child_count(annotation->root); ++index) {
        TSNode node = ts_node_named_child(annotation->root, index);
        if (!kind(node, "import_declaration"))
            continue;
        Slice path = import_path(annotation, node);
        if (!ts_node_is_null(child_of_kind(node, "asterisk"))) {
            if (!is(path, "java.lang") && !is(path, "java.lang.annotation"))
                ambiguous = true;
        } else if (equal(last_name(path), spelling)) {
            return equal(path, target) && ts_node_is_null(child_of_kind(node, "static"));
        }
    }
    return implicit_java_lang && !ambiguous;
}

static int check_meta(JavaFile *annotation, TSNode modifiers)
{
    static const char *const metadata[] = {
        "java.lang.annotation.Target", "java.lang.annotation.Retention",
        "java.lang.annotation.Documented", "java.lang.annotation.Repeatable",
        "java.lang.annotation.Inherited",
    };
    for (uint32_t index = 0; index < ts_node_child_count(modifiers); ++index) {
        TSNode node = ts_node_child(modifiers, index);
        if (ts_node_is_extra(node) || kind(node, "public"))
            continue;
        if (!kind(node, "annotation") && !kind(node, "marker_annotation"))
            return diagnostic(annotation, node, "unsupported annotation modifier");
        Slice name = node_text(annotation, member(node, "name"));
        size_t match = 0;
        while (match < sizeof metadata / sizeof *metadata &&
               !resolves(annotation, name, metadata[match], false))
            ++match;
        if (match == sizeof metadata / sizeof *metadata)
            return diagnostic(annotation, node, "unsupported meta-annotation");
        if (!strcmp(metadata[match], "java.lang.annotation.Inherited"))
            annotation->inherited = true;
    }
    return 0;
}

static const Type *identify_type(const JavaFile *annotation, TSNode node)
{
    static const Type types[] = {
        {"boolean", "bool"}, {"byte", "byte"}, {"short", "short"},
        {"int", "int"}, {"long", "long"}, {"float", "float"},
        {"double", "double"}, {"char", "wchar"}, {"String", "string"},
    };
    static const Type class_type = {"Class", "ClassRef"};
    TSNode base = kind(node, "generic_type") ? ts_node_named_child(node, 0) : node;
    if (resolves(annotation, node_text(annotation, base), "java.lang.Class", true))
        return &class_type;
    Slice name = node_text(annotation, node);
    for (size_t index = 0; index < sizeof types / sizeof *types; ++index) {
        const Type *type = &types[index];
        if (!strcmp(type->java, "String")) {
            if (resolves(annotation, name, "java.lang.String", true))
                return type;
        } else if (is(name, type->java)) {
            return type;
        }
    }
    return NULL;
}

static bool text_literal(Slice value)
{
    for (size_t index = 1; index + 1 < value.length; ++index) {
        unsigned char byte = (unsigned char)value.bytes[index];
        if (byte < 32)
            return false;
        if (byte == '\\' && (++index + 1 >= value.length ||
                !strchr("btnfr\\\"'", value.bytes[index])))
            return false;
    }
    return true;
}

static unsigned integral_base(TSNode node)
{
    if (kind(node, "decimal_integer_literal"))
        return 10;
    if (kind(node, "hex_integer_literal"))
        return 16;
    if (kind(node, "octal_integer_literal"))
        return 8;
    if (kind(node, "binary_integer_literal"))
        return 2;
    return 0;
}

static unsigned digit_value(char byte)
{
    if (digit(byte))
        return (unsigned)(byte - '0');
    if (byte >= 'a' && byte <= 'f')
        return (unsigned)(byte - 'a') + 10;
    if (byte >= 'A' && byte <= 'F')
        return (unsigned)(byte - 'A') + 10;
    return 16;
}

static bool integral_bits(Slice value, unsigned base, uint64_t limit, uint64_t *bits)
{
    size_t start = base == 2 || base == 16 ? 2 : 0;
    if (start >= value.length)
        return false;
    *bits = 0;
    for (size_t index = start; index < value.length; ++index) {
        char byte = value.bytes[index];
        if (byte == '_')
            continue;
        unsigned digit = digit_value(byte);
        if (digit >= base || *bits > (limit - digit) / base)
            return false;
        *bits = *bits * base + digit;
    }
    return true;
}

static bool integral_default(Text *output, Slice value, const Type *type, unsigned base, bool negative)
{
    uint64_t field_maximum;
    if (!strcmp(type->java, "byte"))
        field_maximum = INT8_MAX;
    else if (!strcmp(type->java, "short"))
        field_maximum = INT16_MAX;
    else if (!strcmp(type->java, "int"))
        field_maximum = INT32_MAX;
    else if (!strcmp(type->java, "long"))
        field_maximum = INT64_MAX;
    else
        return false;

    char last = value.length ? value.bytes[value.length - 1] : 0;
    bool long_literal = last == 'l' || last == 'L';
    if (long_literal) {
        if (field_maximum != INT64_MAX)
            return false;
        --value.length;
    }

    // JLS 3.10.1 and 15.15.4: interpret the literal and negate it at its Java width before assignment.
    uint64_t mask = long_literal ? UINT64_MAX : UINT32_MAX;
    uint64_t limit = base == 10 ? (mask >> 1) + negative : mask;
    uint64_t bits;
    if (!integral_bits(value, base, limit, &bits))
        return false;
    if (negative)
        bits = (0 - bits) & mask;
    negative = bits > (mask >> 1);
    uint64_t number = negative ? (0 - bits) & mask : bits;
    if (number > field_maximum + negative)
        return false;
    if (negative && number == (uint64_t)INT64_MAX + 1) {
        add(output, "long.min");
        return !output->failed;
    }
    char number_text[32];
    int length = snprintf(number_text, sizeof number_text, "%s%" PRIu64 "%s",
                          negative ? "-" : "", number, long_literal ? "L" : "");
    return append(output, (Slice){number_text, (size_t)length});
}

static bool scalar_default(const JavaFile *annotation, Text *output, TSNode value, const Type *type)
{
    bool negative = false;
    bool signed_expression = kind(value, "unary_expression");
    if (signed_expression) {
        Slice sign = node_text(annotation, member(value, "operator"));
        negative = is(sign, "-");
        if (!negative && !is(sign, "+"))
            return false;
        value = member(value, "operand");
    }
    Slice text = node_text(annotation, value);
    unsigned base = integral_base(value);
    if (base)
        return integral_default(output, text, type, base, negative);
    if (signed_expression)
        return false;
    if (!strcmp(type->java, "Class") && kind(value, "class_literal") && is(text, "void.class")) {
        add(output, "ClassRef.init");
        return !output->failed;
    }
    if ((!strcmp(type->java, "boolean") && (kind(value, "true") || kind(value, "false"))) ||
        (!strcmp(type->java, "String") && kind(value, "string_literal") && text_literal(text)) ||
        (!strcmp(type->java, "char") && kind(value, "character_literal") && text_literal(text)))
        return append(output, text);
    return false;
}

static bool array_default(const JavaFile *annotation, Text *output, TSNode value, const Type *type)
{
    add(output, "[");
    if (kind(value, "element_value_array_initializer")) {
        bool first = true;
        for (uint32_t index = 0; index < ts_node_named_child_count(value); ++index) {
            TSNode element = ts_node_named_child(value, index);
            if (ts_node_is_extra(element))
                continue;
            if (!first)
                add(output, ", ");
            if (!scalar_default(annotation, output, element, type))
                return false;
            first = false;
        }
    } else if (!scalar_default(annotation, output, value, type)) {
        return false;
    }
    add(output, "]");
    return !output->failed;
}

static bool enum_constant(const JavaFile *java, TSNode node)
{
    return (kind(node, "identifier") || kind(node, "field_access")) && qualified_identifier(node_text(java, node));
}

static int emit_enum_field(const JavaFile *java, Field *field, TSNode type, size_t offset)
{
    Slice spelling = node_text(java, type);
    if (!qualified_identifier(spelling) || is(spelling, "String") || is(spelling, "Class"))
        return diagnostic(java, type, "unsupported annotation type");
    field->enum_type = spelling;
    field->offset = offset;
    TSNode value = member(field->node, "value");
    field->enum_default = value;
    if (ts_node_is_null(value))
        return 0;
    if (field->array && kind(value, "element_value_array_initializer")) {
        for (uint32_t index = 0; index < ts_node_named_child_count(value); ++index) {
            TSNode element = ts_node_named_child(value, index);
            if (!ts_node_is_extra(element) && !enum_constant(java, element))
                return diagnostic(java, element, "unsupported enum annotation default");
        }
    } else if (!enum_constant(java, value)) {
        return diagnostic(java, value, "unsupported enum annotation default");
    }
    return 0;
}

static int emit_field(JavaFile *annotation, Field *field, Text *output)
{
    TSNode node = field->node;
    TSNode type_node = member(node, "type");
    TSNode dimensions = member(node, "dimensions");
    bool array = kind(type_node, "array_type") || !ts_node_is_null(dimensions);
    if (kind(type_node, "array_type")) {
        if (!ts_node_is_null(dimensions))
            return diagnostic(annotation, node, "unsupported annotation type");
        dimensions = member(type_node, "dimensions");
        type_node = member(type_node, "element");
    }
    const Type *type = identify_type(annotation, type_node);
    if ((array && !is(node_text(annotation, dimensions), "[]")) ||
        !ts_node_is_null(child_of_kind(node, "modifiers")))
        return diagnostic(annotation, node, "unsupported annotation type");
    field->array = array;
    if (!type)
        return emit_enum_field(annotation, field, type_node, output->length);
    if (!strcmp(type->java, "Class"))
        annotation->class_ref = true;

    add(output, "    ");
    add(output, type->d);
    if (array)
        add(output, "[]");
    add(output, " ");
    append(output, contents(&field->symbol));
    TSNode value = member(node, "value");
    if (!ts_node_is_null(value)) {
        add(output, " = ");
        bool supported = array ? array_default(annotation, output, value, type)
                               : scalar_default(annotation, output, value, type);
        if (!supported)
            return diagnostic(annotation, value, "unsupported annotation default");
    }
    add(output, ";\n");
    return 0;
}

static bool has_declarations(TSNode node)
{
    for (uint32_t index = 0; index < ts_node_named_child_count(node); ++index)
        if (!ts_node_is_extra(ts_node_named_child(node, index)))
            return true;
    return false;
}

static bool plain_constant(TSNode node)
{
    return kind(node, "enum_constant") && ts_node_is_null(member(node, "arguments"))
        && ts_node_is_null(member(node, "body"))
        && ts_node_is_null(child_of_kind(node, "modifiers"));
}

static int collect_fields(const JavaFile *annotation, TSNode body, Field *fields, size_t *count)
{
    for (uint32_t index = 0; index < ts_node_named_child_count(body); ++index) {
        TSNode node = ts_node_named_child(body, index);
        if (ts_node_is_extra(node))
            continue;
        if (annotation->is_enum && kind(node, "enum_body_declarations") && !has_declarations(node))
            continue;
        if (annotation->is_enum && !plain_constant(node))
            return diagnostic(annotation, node, "unsupported enum member");
        if (!annotation->is_enum && !kind(node, "annotation_type_element_declaration"))
            return diagnostic(annotation, node, "unsupported annotation member");
        Slice name = node_text(annotation, member(node, "name"));
        Field *field = &fields[(*count)++];
        field->name = name;
        field->node = node;
        if (!lower_name(name, &field->symbol))
            return diagnostic(annotation, node, "unsupported member name");
        for (size_t earlier = 0; earlier + 1 < *count; ++earlier) {
            if (equal(contents(&fields[earlier].symbol), contents(&field->symbol)))
                return diagnostic(annotation, node, "member names collide in D");
        }
        if (!annotation->is_enum && is(name, "value") && *count > 1) {
            Field value = *field;
            memmove(fields + 1, fields, (*count - 1) * sizeof *fields);
            fields[0] = value;
        }
    }
    if (annotation->is_enum && !*count)
        return diagnostic(annotation, body, "unsupported enum without constants");
    return 0;
}

static void json_string(Slice text)
{
    putchar('"');
    for (size_t index = 0; index < text.length; ++index) {
        unsigned char byte = (unsigned char)text.bytes[index];
        if (byte == '"' || byte == '\\')
            putchar('\\');
        if (byte < 32)
            printf("\\u%04x", (unsigned int)byte);
        else
            putchar(byte);
    }
    putchar('"');
}

static void emit_enum_reference(const JavaFile *java, const Field *field)
{
    fputs(",\"enum\":{\"type\":", stdout);
    json_string(field->enum_type);
    printf(",\"offset\":%zu,\"array\":%s,\"defaults\":", field->offset, field->array ? "true" : "false");
    TSNode value = field->enum_default;
    if (ts_node_is_null(value)) {
        fputs("null}", stdout);
        return;
    }
    putchar('[');
    if (kind(value, "element_value_array_initializer")) {
        bool first = true;
        for (uint32_t index = 0; index < ts_node_named_child_count(value); ++index) {
            TSNode element = ts_node_named_child(value, index);
            if (ts_node_is_extra(element))
                continue;
            if (!first)
                putchar(',');
            json_string(node_text(java, element));
            first = false;
        }
    } else {
        json_string(node_text(java, value));
    }
    fputs("]}", stdout);
}

static void emit_imports(const JavaFile *java)
{
    fputs(",\"enumImports\":[", stdout);
    bool first = true;
    for (uint32_t index = 0; index < ts_node_named_child_count(java->root); ++index) {
        TSNode node = ts_node_named_child(java->root, index);
        if (!kind(node, "import_declaration"))
            continue;
        fputs(first ? "{\"path\":" : ",{\"path\":", stdout);
        json_string(import_path(java, node));
        printf(",\"static\":%s,\"wildcard\":%s}",
               ts_node_is_null(child_of_kind(node, "static")) ? "false" : "true",
               ts_node_is_null(child_of_kind(node, "asterisk")) ? "false" : "true");
        first = false;
    }
    putchar(']');
}

static void emit_candidate(const JavaFile *annotation, Slice name, const Text *symbol,
                           const Field *fields, size_t count, const Text *body)
{
    fputs("{\"package\":", stdout);
    json_string(annotation->package);
    fputs(",\"name\":", stdout);
    json_string(name);
    fputs(",\"symbol\":", stdout);
    json_string(contents(symbol));
    fputs(annotation->is_enum ? ",\"kind\":\"enum\"" : ",\"kind\":\"annotation\"", stdout);
    fputs(",\"members\":[", stdout);
    bool has_enum_fields = false;
    for (size_t index = 0; index < count; ++index) {
        fputs(index ? ",{\"name\":" : "{\"name\":", stdout);
        json_string(fields[index].name);
        fputs(",\"symbol\":", stdout);
        json_string(contents(&fields[index].symbol));
        if (fields[index].enum_type.length) {
            has_enum_fields = true;
            emit_enum_reference(annotation, &fields[index]);
        }
        putchar('}');
    }
    printf("],\"inherited\":%s,\"classRef\":%s,\"%s\":", annotation->inherited ? "true" : "false",
           annotation->class_ref ? "true" : "false", has_enum_fields ? "enumBody" : "body");
    json_string(contents(body));
    if (has_enum_fields)
        emit_imports(annotation);
    puts("}");
}

static int translate(JavaFile *annotation)
{
    if (ts_node_has_error(annotation->root))
        return diagnostic(annotation, annotation->root, "Java syntax error");
    if (!package_and_declaration(annotation))
        return diagnostic(annotation, annotation->root, "expected a package and one public annotation or enum");
    if (annotation->is_enum && !ts_node_is_null(member(annotation->declaration, "interfaces")))
        return diagnostic(annotation, annotation->declaration, "unsupported enum implementing an interface");
    int status = check_meta(annotation, child_of_kind(annotation->declaration, "modifiers"));
    if (status)
        return status;

    TSNode body = member(annotation->declaration, "body");
    size_t slots = ts_node_named_child_count(body);
    Field *fields = calloc(slots ? slots : 1, sizeof *fields);
    if (!fields)
        return diagnostic(annotation, body, "cannot allocate members");
    size_t count = 0;
    Text output = {0};
    Text symbol = {0};
    Slice name = node_text(annotation, member(annotation->declaration, "name"));
    if (!lower_name(name, &symbol)) {
        status = diagnostic(annotation, annotation->declaration, "unsupported declaration name");
        goto cleanup;
    }
    status = collect_fields(annotation, body, fields, &count);
    if (status)
        goto cleanup;
    add(&output, annotation->is_enum ? "enum " : "struct ");
    append(&output, contents(&symbol));
    add(&output, "\n{\n");
    for (size_t index = 0; index < count; ++index) {
        if (annotation->is_enum) {
            add(&output, "    ");
            append(&output, contents(&fields[index].symbol));
            add(&output, ",\n");
        } else {
            status = emit_field(annotation, &fields[index], &output);
            if (status)
                goto cleanup;
        }
    }
    add(&output, "}\n");
    if (output.failed) {
        status = diagnostic(annotation, body, "cannot allocate output");
        goto cleanup;
    }
    emit_candidate(annotation, name, &symbol, fields, count, &output);
    if (fflush(stdout) == EOF)
        status = diagnostic(annotation, body, "cannot write output");
cleanup:
    for (size_t index = 0; index < count; ++index)
        free(fields[index].symbol.bytes);
    free(fields);
    free(output.bytes);
    free(symbol.bytes);
    return status;
}

static char *read_source(const char *path, uint32_t *size)
{
    FILE *file = fopen(path, "rb");
    if (!file)
        return NULL;
    char *source = NULL;
    if (!fseek(file, 0, SEEK_END)) {
        long length = ftell(file);
        if (length >= 0 && (uintmax_t)length < UINT32_MAX && !fseek(file, 0, SEEK_SET)) {
            *size = (uint32_t)length;
            source = malloc(length ? (size_t)length : 1);
            if (source && fread(source, 1, *size, file) != *size) {
                free(source);
                source = NULL;
            }
        }
    }
    fclose(file);
    return source;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fputs("usage: flint-port-spring <Java file>\n", stderr);
        return 1;
    }
    uint32_t size;
    char *source = read_source(argv[1], &size);
    if (!source) {
        fprintf(stderr, "%s: cannot read Java source\n", argv[1]);
        return 1;
    }
    TSParser *parser = ts_parser_new();
    TSTree *tree = NULL;
    if (parser && ts_parser_set_language(parser, tree_sitter_java()))
        tree = ts_parser_parse_string(parser, NULL, source, size);
    int status = 1;
    if (tree) {
        JavaFile annotation = {.source = source, .path = argv[1], .root = ts_tree_root_node(tree)};
        status = translate(&annotation);
        ts_tree_delete(tree);
    } else {
        fputs("cannot parse with the pinned Java grammar\n", stderr);
    }
    if (parser)
        ts_parser_delete(parser);
    free(source);
    return status;
}
