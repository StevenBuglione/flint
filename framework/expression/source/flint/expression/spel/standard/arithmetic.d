/*
 * Copyright 2002-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from spring-framework v7.1.0: spring-expression/src/main/java/org/springframework/expression/spel/ast/OpPlus.java
 * Also from OpMinus.java, OpMultiply.java, OpDivide.java, OpModulus.java, OperatorPower.java,
 * Operator.java, OpEQ.java, OpNE.java, OpLT.java, OpLE.java, OpGT.java, OpGE.java,
 * OpAnd.java, OpOr.java and OperatorNot.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard.arithmetic;

import core.stdc.math : pow;
import flint.arena : Error, Result, Status;
import flint.engine.aot.any : Any;
import flint.engine.aot.text : decodeUtf8;
import flint.expression.spel : SpelMessage;
import flint.expression.spel.standard.literal : LiteralParser;
import flint.java.character : isLetter;
import flint.java.lang : IllegalArgumentException;
import std.ascii : isAlpha, isDigit, toLower;

@safe:
package(flint.expression.spel.standard):

/// SpEL v7.1's default nesting limit. There can be two pending binary operators at each level.
private enum maxNesting = 200;
private enum maxStack = 2 * (maxNesting + 1) + 1;

/// A scalar, a standalone variable, or a scalar expression stored in evaluation order.
struct ArithmeticExpression
{
    private Any constant;
    private immutable(Instruction)[] instructions;
    string variable;

    Result!Any evaluate() nothrow @nogc
    {
        if (instructions.length == 0)
            return Result!Any(constant);
        enum shortStack = 16;
        if (instructions.length < 2 * shortStack)
        {
            Scalar[shortStack] stack;
            return evaluateStack(stack);
        }
        Scalar[maxStack] stack;
        return evaluateStack(stack);
    }

    private Result!Any evaluateStack(scope Scalar[] stack) nothrow @nogc
    {
        size_t depth;
        for (size_t next; next < instructions.length;)
        {
            const instruction = &instructions[next++];
            if (instruction.op == Op.literal)
            {
                stack[depth++] = instruction.value;
                continue;
            }
            if (instruction.op >= Op.positive)
            {
                const error = instruction.op < Op.and_ ? stepSign(*instruction,
                        stack[depth - 1]) : stepBoolean(*instruction, stack[depth - 1], depth, next);
                if (error.code != Status.ok)
                    return Result!Any(Any.init, error);
                continue;
            }
            const right = stack[--depth];
            const result = applyOperator(instruction.op, stack[depth - 1], right);
            if (!result.ok())
                return Result!Any(Any.init, Error(result.error.code, result.error.message, instruction.position));
            stack[depth - 1] = result.value;
        }
        return Result!Any(stack[0].pack());
    }
}

ArithmeticExpression parseArithmetic(string source)
{
    ArithmeticParser parser = ArithmeticParser(LiteralParser(source));
    parser.reader.skipWhitespace();
    if (parser.reader.position == source.length)
        throw new IllegalArgumentException("'expressionString' must not be null or blank");
    parser.parse(orPrecedence, 0);
    const end = parser.reader.position;
    if (end < source.length)
        throw parser.reader.errorAt(end, SpelMessage.MORE_INPUT, source[end .. $]);
    if (parser.instructions.length == 0)
        return ArithmeticExpression(parser.firstLiteral, null, parser.variable);
    return ArithmeticExpression(Any.init, parser.instructions.idup);
}

private enum Op : ubyte
{
    literal,
    add,
    subtract,
    multiply,
    divide,
    modulus,
    power,
    equal,
    notEqual,
    less,
    lessEqual,
    greater,
    greaterEqual,
    positive,
    negative,
    and_,
    or_,
    not_,
    requireBoolean,
}

private struct Instruction
{
    Op op;
    size_t position;
    Scalar value;
    size_t jump;
}

private struct ArithmeticParser
{
    LiteralParser reader;
    Instruction[] instructions;
    Any firstLiteral;
    size_t firstPosition = size_t.max;
    string variable;

    size_t parse(ubyte minimumPrecedence, uint nesting)
    {
        size_t left = parsePower(nesting);
        ubyte maximumPrecedence = ubyte.max;
        while (true)
        {
            reader.skipWhitespace();
            const position = reader.position;
            const token = operatorToken(reader.text[position .. $]);
            if (token.precedence < minimumPrecedence || token.precedence > maximumPrecedence || variable !is null)
                return left;
            reader.position += token.length;
            const rhsPrecedence = cast(ubyte)(token.precedence + 1);
            if (token.op == Op.and_ || token.op == Op.or_)
                logical(token.op, left, rhsPrecedence, nesting);
            else
            {
                parse(rhsPrecedence, nesting);
                instructions ~= Instruction(token.op, position);
            }
            // A comparison may be followed by a lower-precedence boolean operator.
            maximumPrecedence = token.precedence == comparisonPrecedence
                ? cast(ubyte)(comparisonPrecedence - 1) : token.precedence;
            left = position;
        }
    }

    size_t parsePower(uint nesting)
    {
        const left = primary(nesting);
        reader.skipWhitespace();
        if (reader.peek != '^' || variable !is null)
            return left;
        const position = reader.position++;
        primary(nesting);
        instructions ~= Instruction(Op.power, position);
        return position;
    }

    void logical(Op op, size_t left, ubyte rhsPrecedence, uint nesting)
    {
        emitFirstLiteral();
        const branch = instructions.length;
        instructions ~= Instruction(op, left);
        const right = parse(rhsPrecedence, nesting);
        instructions ~= Instruction(Op.requireBoolean, right);
        instructions[branch].jump = instructions.length;
    }

    size_t primary(uint nesting)
    {
        reader.skipWhitespace();
        const position = reader.position;
        const negation = notOperator(reader.text[position .. $]);
        if (negation)
        {
            checkNesting(nesting);
            reader.position += negation;
            const operand = primary(nesting + 1);
            emitFirstLiteral();
            instructions ~= Instruction(Op.not_, operand);
            return position;
        }
        if (readSign(nesting))
            return position;
        if (reader.peek == '(')
        {
            checkNesting(nesting);
            ++reader.position;
            const inner = parse(orPrecedence, nesting + 1);
            if (reader.peek != ')')
                throw reader.errorAt(reader.position, SpelMessage.OOD);
            ++reader.position;
            return inner;
        }
        if (reader.peek == '#' && firstPosition == size_t.max)
        {
            variable = readVariableName();
            firstPosition = position;
        }
        else
            literal(position);
        return position;
    }

    bool readSign(uint nesting)
    {
        const sign = reader.peek;
        if (sign != '+' && sign != '-')
            return false;
        auto operand = reader;
        ++operand.position;
        // Spring considers an adjacent pair an increment or decrement operator.
        if (operand.peek == sign)
            throw reader.errorAt(operand.position, SpelMessage.OOD);
        operand.skipWhitespace();
        if (isDigit(operand.peek))
            return false;

        const position = reader.position;
        checkNesting(nesting);
        reader.position = operand.position;
        primary(nesting + 1);
        emitFirstLiteral();
        instructions ~= Instruction(sign == '+' ? Op.positive : Op.negative, position);
        return true;
    }

    void checkNesting(uint nesting)
    {
        if (nesting == maxNesting)
            throw reader.errorAt(reader.position, SpelMessage.MAX_EXPRESSION_NESTING_DEPTH_EXCEEDED, "200");
    }

    string readVariableName()
    {
        ++reader.position;
        reader.skipWhitespace();
        const start = reader.position;
        size_t end = start;
        if (start == reader.text.length || !startsIdentifier(decodeUtf8(reader.text, end)))
            throw reader.errorAt(start, SpelMessage.OOD);
        reader.position = end;
        while (end < reader.text.length)
        {
            const next = decodeUtf8(reader.text, end);
            if (!startsIdentifier(next) && (next < '0' || next > '9'))
                break;
            reader.position = end;
        }
        return reader.text[start .. reader.position];
    }

    void literal(size_t position)
    {
        if (firstPosition == size_t.max)
        {
            firstLiteral = reader.readLiteral();
            firstPosition = position;
            return;
        }
        emitFirstLiteral();
        const scalar = reader.readLiteral();
        instructions ~= Instruction(Op.literal, position, Scalar.from(scalar));
    }

    void emitFirstLiteral()
    {
        if (instructions.length != 0)
            return;
        if (variable !is null)
            throw reader.errorAt(firstPosition, SpelMessage.OOD);
        instructions ~= Instruction(Op.literal, firstPosition, Scalar.from(firstLiteral));
    }
}

// Spring's tokenizer applies Character.isLetter to one UTF-16 code unit at a time.
private bool startsIdentifier(dchar c) pure nothrow @nogc
{
    return c == '_' || c == '$' || (c <= 0xFFFF && isLetter(c));
}

private enum ubyte orPrecedence = 1;
private enum ubyte andPrecedence = 2;
private enum ubyte comparisonPrecedence = 3;
private enum ubyte sumPrecedence = 4;
private enum ubyte productPrecedence = 5;

private struct OperatorToken
{
    Op op;
    ubyte precedence;
    ubyte length;
}

private struct OperatorSpelling
{
    string text;
    Op op;
    ubyte precedence;

    OperatorToken token() const pure nothrow @nogc
    {
        return OperatorToken(op, precedence, cast(ubyte) text.length);
    }
}

private immutable OperatorSpelling[] symbolOperators = [
    OperatorSpelling("||", Op.or_, orPrecedence), OperatorSpelling("&&", Op.and_, andPrecedence),
    OperatorSpelling("==", Op.equal, comparisonPrecedence),
    OperatorSpelling("!=", Op.notEqual, comparisonPrecedence),
    OperatorSpelling("<=", Op.lessEqual, comparisonPrecedence),
    OperatorSpelling(">=", Op.greaterEqual, comparisonPrecedence),
    OperatorSpelling("<", Op.less, comparisonPrecedence),
    OperatorSpelling(">", Op.greater, comparisonPrecedence),
    OperatorSpelling("+", Op.add, sumPrecedence), OperatorSpelling("-", Op.subtract,
            sumPrecedence), OperatorSpelling("*", Op.multiply, productPrecedence),
    OperatorSpelling("/", Op.divide, productPrecedence),
    OperatorSpelling("%", Op.modulus, productPrecedence),
];

private immutable OperatorSpelling[] alternateOperators = [
    OperatorSpelling("or", Op.or_, orPrecedence), OperatorSpelling("and", Op.and_, andPrecedence),
    OperatorSpelling("eq", Op.equal, comparisonPrecedence),
    OperatorSpelling("ne", Op.notEqual, comparisonPrecedence),
    OperatorSpelling("lt", Op.less, comparisonPrecedence),
    OperatorSpelling("le", Op.lessEqual, comparisonPrecedence),
    OperatorSpelling("gt", Op.greater, comparisonPrecedence),
    OperatorSpelling("ge", Op.greaterEqual, comparisonPrecedence),
    OperatorSpelling("div", Op.divide, productPrecedence),
    OperatorSpelling("mod", Op.modulus, productPrecedence),
];

private ubyte notOperator(scope const(char)[] tail) pure nothrow @nogc
{
    if (tail.length && tail[0] == '!' && (tail.length == 1 || tail[1] != '='))
        return 1;
    if (tail.length >= 3 && toLower(tail[0]) == 'n' && toLower(tail[1]) == 'o'
            && toLower(tail[2]) == 't' && !continuesIdentifier(tail, 3))
        return 3;
    return 0;
}

private OperatorToken operatorToken(scope const(char)[] tail) pure nothrow @nogc
{
    if (tail.length == 0)
        return OperatorToken.init;
    if (tail.length >= 2 && tail[0] == tail[1] && (tail[0] == '+' || tail[0] == '-'))
        return OperatorToken.init;
    if (isAlpha(tail[0]))
        return wordOperator(tail);
    foreach (entry; symbolOperators)
        if (tail.length >= entry.text.length && tail[0 .. entry.text.length] == entry.text)
            return entry.token();
    return OperatorToken.init;
}

private OperatorToken wordOperator(scope const(char)[] tail) pure nothrow @nogc
{
    char[3] word;
    size_t width;
    while (width < tail.length && width < word.length && isAlpha(tail[width]))
    {
        word[width] = toLower(tail[width]);
        ++width;
    }
    if (width < 2 || continuesIdentifier(tail, width))
        return OperatorToken.init;
    foreach (entry; alternateOperators)
        if (word[0 .. width] == entry.text)
            return entry.token();
    return OperatorToken.init;
}

private bool continuesIdentifier(scope const(char)[] tail, size_t index) pure nothrow @nogc
{
    if (index == tail.length)
        return false;
    const next = decodeUtf8(tail, index);
    return startsIdentifier(next) || (next >= '0' && next <= '9');
}

private enum ValueKind : ubyte
{
    other,
    int_,
    long_,
    float_,
    double_,
    null_,
    bool_,
    string_,
}

private struct Scalar
{
    ValueKind kind;
    long integer;
    double realValue;
    string text;

    static Scalar from(const ref Any scalar)
    {
        if (scalar.isNull())
            return Scalar(ValueKind.null_);
        switch (scalar.typeName())
        {
        case "bool":
            return Scalar(ValueKind.bool_, scalar.get!bool);
        case "string":
            return Scalar(ValueKind.string_, 0, 0, scalar.get!string);
        case "int":
            return Scalar(ValueKind.int_, scalar.get!int);
        case "long":
            return Scalar(ValueKind.long_, scalar.get!long);
        case "float":
            return Scalar(ValueKind.float_, 0, scalar.get!float);
        case "double":
            return Scalar(ValueKind.double_, 0, scalar.get!double);
        default:
            return Scalar.init;
        }
    }

    float asFloat() const pure nothrow @nogc
    {
        return kind >= ValueKind.float_ ? cast(float) realValue : cast(float) integer;
    }

    double asDouble() const pure nothrow @nogc
    {
        return kind >= ValueKind.float_ ? realValue : cast(double) integer;
    }

    Any pack() const pure nothrow @nogc
    {
        final switch (kind)
        {
        case ValueKind.other, ValueKind.null_:
            return Any.init;
        case ValueKind.bool_:
            return Any.of(integer != 0);
        case ValueKind.string_:
            return Any.of(text);
        case ValueKind.int_:
            return Any.of(cast(int) integer);
        case ValueKind.long_:
            return Any.of(integer);
        case ValueKind.float_:
            return Any.of(cast(float) realValue);
        case ValueKind.double_:
            return Any.of(realValue);
        }
    }
}

private Result!Scalar applyOperator(Op op, Scalar left, Scalar right) nothrow @nogc
{
    if (op >= Op.equal && op <= Op.greaterEqual)
        return compare(op, left, right);
    if (!isNumber(left.kind) || !isNumber(right.kind))
        return Result!Scalar(Scalar.init, Error(Status.unsupported, "SpEL arithmetic requires numeric operands"));
    const kind = left.kind >= right.kind ? left.kind : right.kind;
    if (op == Op.power)
        return Result!Scalar(power(kind, left, right));
    if (kind == ValueKind.double_)
        return Result!Scalar(Scalar(kind, 0, arithmetic(op, left.asDouble(), right.asDouble())));
    if (kind == ValueKind.float_)
        return Result!Scalar(Scalar(kind, 0, arithmetic(op, left.asFloat(), right.asFloat())));
    return integerArithmetic(op, kind, left.integer, right.integer);
}

private Error stepSign(const ref Instruction step, ref Scalar value) nothrow @nogc
{
    if (!isNumber(value.kind))
        return Error(Status.unsupported, "SpEL unary sign requires a numeric operand", step.position);
    if (step.op == Op.negative)
    {
        const result = applyOperator(Op.subtract, Scalar(value.kind, 0, 0), value);
        if (!result.ok())
            return Error(result.error.code, result.error.message, step.position);
        value = result.value;
    }
    return Error.init;
}

private enum BooleanValue : ubyte
{
    invalid,
    missing,
    no,
    yes,
}

private Error stepBoolean(const ref Instruction step, ref Scalar top, ref size_t used, ref size_t pc) pure nothrow @nogc
{
    const value = asBoolean(top);
    if (value < BooleanValue.no)
    {
        const type = value == BooleanValue.missing ? "null" : sourceType(top.kind);
        return Error(Status.conflict, type, step.position);
    }
    const truth = value == BooleanValue.yes;
    switch (step.op)
    {
    case Op.not_:
        top = Scalar(ValueKind.bool_, !truth);
        break;
    case Op.requireBoolean:
        top = Scalar(ValueKind.bool_, truth);
        break;
    default:
        if (truth == (step.op == Op.or_))
        {
            top = Scalar(ValueKind.bool_, truth);
            pc = step.jump;
        }
        else
            --used;
    }
    return Error.init;
}

private BooleanValue asBoolean(const ref Scalar scalar) pure nothrow @nogc
{
    if (scalar.kind == ValueKind.bool_)
        return scalar.integer ? BooleanValue.yes : BooleanValue.no;
    if (scalar.kind == ValueKind.null_)
        return BooleanValue.missing;
    if (scalar.kind != ValueKind.string_)
        return BooleanValue.invalid;
    return textBoolean(scalar.text);
}

private BooleanValue textBoolean(scope const(char)[] text) pure nothrow @nogc
{
    while (text.length && text[0] <= ' ')
        text = text[1 .. $];
    while (text.length && text[$ - 1] <= ' ')
        text = text[0 .. $ - 1];
    if (text.length == 0)
        return BooleanValue.missing;
    char[5] word;
    if (text.length > word.length)
        return BooleanValue.invalid;
    foreach (i, ch; text)
        word[i] = toLower(ch);
    switch (word[0 .. text.length])
    {
    case "true", "on", "yes", "1":
        return BooleanValue.yes;
    case "false", "off", "no", "0":
        return BooleanValue.no;
    default:
        return BooleanValue.invalid;
    }
}

private string sourceType(ValueKind kind) pure nothrow @nogc
{
    final switch (kind)
    {
    case ValueKind.other:
        return "java.lang.Object";
    case ValueKind.int_:
        return "java.lang.Integer";
    case ValueKind.long_:
        return "java.lang.Long";
    case ValueKind.float_:
        return "java.lang.Float";
    case ValueKind.double_:
        return "java.lang.Double";
    case ValueKind.null_:
        return "null";
    case ValueKind.bool_:
        return "java.lang.Boolean";
    case ValueKind.string_:
        return "java.lang.String";
    }
}

private bool isNumber(ValueKind kind) pure nothrow @nogc
{
    return kind >= ValueKind.int_ && kind <= ValueKind.double_;
}

private enum Order : ubyte
{
    less,
    equal,
    greater,
    unordered,
    incomparable,
}

private Result!Scalar compare(Op op, Scalar left, Scalar right) pure nothrow @nogc
{
    const order = compareValues(left, right);
    if (order == Order.incomparable && op != Op.equal && op != Op.notEqual)
        return Result!Scalar(Scalar.init, Error(Status.unsupported, "SpEL operands are not comparable"));
    return Result!Scalar(Scalar(ValueKind.bool_, comparisonMatches(op, order)));
}

private bool comparisonMatches(Op op, Order order) pure nothrow @nogc
{
    switch (op)
    {
    case Op.equal:
        return order == Order.equal;
    case Op.notEqual:
        return order != Order.equal;
    case Op.less:
        return order == Order.less;
    case Op.lessEqual:
        return order == Order.less || order == Order.equal;
    case Op.greater:
        return order == Order.greater;
    case Op.greaterEqual:
        return order == Order.greater || order == Order.equal;
    default:
        assert(0, "Not a comparison operator");
    }
}

private Order compareValues(Scalar left, Scalar right) pure nothrow @nogc
{
    if (left.kind == ValueKind.null_ || right.kind == ValueKind.null_)
        return compareOrdered(left.kind != ValueKind.null_, right.kind != ValueKind.null_);
    if (isNumber(left.kind) && isNumber(right.kind))
    {
        if (left.kind == ValueKind.double_ || right.kind == ValueKind.double_)
            return compareOrdered(left.asDouble(), right.asDouble());
        if (left.kind == ValueKind.float_ || right.kind == ValueKind.float_)
            return compareOrdered(left.asFloat(), right.asFloat());
        return compareOrdered(left.integer, right.integer);
    }
    if (left.kind == ValueKind.string_ && right.kind == ValueKind.string_)
        return compareText(left.text, right.text);
    if (left.kind == ValueKind.bool_ && right.kind == ValueKind.bool_)
        return compareOrdered(left.integer, right.integer);
    return Order.incomparable;
}

private Order compareOrdered(T)(T left, T right) pure nothrow @nogc
{
    if (left < right)
        return Order.less;
    if (left > right)
        return Order.greater;
    return left == right ? Order.equal : Order.unordered;
}

private Order compareText(scope const(char)[] left, scope const(char)[] right) pure nothrow @nogc
{
    size_t i, j;
    while (i < left.length && j < right.length)
    {
        const a = decodeUtf8(left, i);
        const b = decodeUtf8(right, j);
        if (a != b)
            return compareOrdered(utf16Order(a), utf16Order(b));
    }
    return compareOrdered(left.length - i, right.length - j);
}

private uint utf16Order(dchar codePoint) pure nothrow @nogc
{
    // Supplementary code points lead with a surrogate and sort before BMP values after the surrogate range.
    return codePoint >= 0xE000 && codePoint <= 0xFFFF ? codePoint + 0x110000 : codePoint;
}

private Scalar power(ValueKind kind, Scalar left, Scalar right) nothrow @nogc
{
    const double base = kind == ValueKind.float_ ? left.asFloat() : left.asDouble();
    const double exponent = kind == ValueKind.float_ ? right.asFloat() : right.asDouble();
    // Math.pow returns NaN here, while C pow treats an absolute base of one as a special case.
    const unitBase = base == 1 || base == -1;
    const nonfiniteExponent = exponent != exponent || exponent == double.infinity || exponent == -double.infinity;
    const result = unitBase && nonfiniteExponent ? double.nan : pow(base, exponent);
    if (kind >= ValueKind.float_)
        return Scalar(ValueKind.double_, 0, result);
    if (kind == ValueKind.long_ || result > int.max)
    {
        if (result >= 0x1p63)
            return Scalar(ValueKind.long_, long.max);
        if (result <= -0x1p63)
            return Scalar(ValueKind.long_, long.min);
        return Scalar(ValueKind.long_, cast(long) result);
    }
    return Scalar(ValueKind.int_, result <= int.min ? int.min : cast(int) result);
}

private Result!Scalar integerArithmetic(Op op, ValueKind kind, long left, long right) pure nothrow @nogc
{
    if (op == Op.divide || op == Op.modulus)
    {
        if (right == 0)
            return Result!Scalar(Scalar.init, Error(Status.invalidArgument, "/ by zero"));
        if (left == long.min && right == -1)
            return Result!Scalar(Scalar(kind, op == Op.divide ? long.min : 0));
    }
    const value = arithmetic(op, left, right);
    return Result!Scalar(Scalar(kind, kind == ValueKind.int_ ? cast(int) value : value));
}

private T arithmetic(T)(Op op, T left, T right) pure nothrow @nogc
{
    switch (op)
    {
    case Op.add:
        return left + right;
    case Op.subtract:
        return left - right;
    case Op.multiply:
        return left * right;
    case Op.divide:
        return left / right;
    case Op.modulus:
        return left % right;
    default:
        assert(0, "Not a basic arithmetic operator");
    }
}
