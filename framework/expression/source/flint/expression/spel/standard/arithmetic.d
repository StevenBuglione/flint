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
 * Also from OpMinus.java, OpMultiply.java, OpDivide.java and OpModulus.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard.arithmetic;

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

/// A scalar, a standalone variable, or an arithmetic tree stored in evaluation order.
struct ArithmeticExpression
{
    private Any constant;
    private immutable(Instruction)[] instructions;
    string variable;

    Result!Any evaluate() pure nothrow @nogc
    {
        if (instructions.length == 0)
            return Result!Any(constant);
        Numeric[maxStack] stack = void;
        size_t depth;
        foreach (ref instruction; instructions)
        {
            if (instruction.op == Op.literal)
            {
                stack[depth++] = instruction.value;
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
    parser.parse(1, 0);
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
}

private struct Instruction
{
    Op op;
    size_t position;
    Numeric value;
}

private struct ArithmeticParser
{
    LiteralParser reader;
    Instruction[] instructions;
    Any firstLiteral;
    size_t firstPosition = size_t.max;
    string variable;

    void parse(ubyte minimumPrecedence, uint nesting)
    {
        primary(nesting);
        while (true)
        {
            reader.skipWhitespace();
            const position = reader.position;
            const token = operatorToken(reader.text[position .. $]);
            if (token.precedence < minimumPrecedence || variable !is null)
                return;
            reader.position += token.length;
            parse(cast(ubyte)(token.precedence + 1), nesting);
            instructions ~= Instruction(token.op, position);
        }
    }

    void primary(uint nesting)
    {
        reader.skipWhitespace();
        const position = reader.position;
        if (reader.peek != '(')
        {
            if (reader.peek == '#' && firstPosition == size_t.max)
            {
                variable = readVariableName();
                firstPosition = position;
            }
            else
                literal(position);
            return;
        }
        if (nesting == maxNesting)
            throw reader.errorAt(position, SpelMessage.MAX_EXPRESSION_NESTING_DEPTH_EXCEEDED, "200");
        ++reader.position;
        parse(1, nesting + 1);
        if (reader.peek != ')')
            throw reader.errorAt(reader.position, SpelMessage.OOD);
        ++reader.position;
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
        if (instructions.length == 0)
            instructions ~= Instruction(Op.literal, firstPosition, Numeric.from(firstLiteral));
        const scalar = reader.readLiteral();
        instructions ~= Instruction(Op.literal, position, Numeric.from(scalar));
    }
}

// Spring's tokenizer applies Character.isLetter to one UTF-16 code unit at a time.
private bool startsIdentifier(dchar c) pure nothrow @nogc
{
    return c == '_' || c == '$' || (c <= 0xFFFF && isLetter(c));
}

private struct OperatorToken
{
    Op op;
    ubyte precedence;
    ubyte length;
}

private OperatorToken operatorToken(scope const(char)[] tail) pure nothrow @nogc
{
    if (tail.length == 0)
        return OperatorToken.init;
    switch (tail[0])
    {
    case '+', '-':
        if (tail.length >= 2 && tail[1] == tail[0])
            return OperatorToken.init;
        return OperatorToken(tail[0] == '+' ? Op.add : Op.subtract, 1, 1);
    case '*':
        return OperatorToken(Op.multiply, 2, 1);
    case '/':
        return OperatorToken(Op.divide, 2, 1);
    case '%':
        return OperatorToken(Op.modulus, 2, 1);
    default:
        return wordOperator(tail);
    }
}

private OperatorToken wordOperator(scope const(char)[] tail) pure nothrow @nogc
{
    if (tail.length < 3 || (tail.length > 3 && isIdentifier(tail[3])))
        return OperatorToken.init;
    char[3] word = [toLower(tail[0]), toLower(tail[1]), toLower(tail[2])];
    if (word[] == "div")
        return OperatorToken(Op.divide, 2, 3);
    if (word[] == "mod")
        return OperatorToken(Op.modulus, 2, 3);
    return OperatorToken.init;
}

private bool isIdentifier(char c) pure nothrow @nogc
{
    return isAlpha(c) || isDigit(c) || c == '_' || c == '$';
}

private enum NumberKind : ubyte
{
    other,
    int_,
    long_,
    float_,
    double_,
}

private struct Numeric
{
    NumberKind kind;
    long integer;
    double realValue;

    static Numeric from(const ref Any scalar)
    {
        switch (scalar.typeName())
        {
        case "int":
            return Numeric(NumberKind.int_, scalar.get!int);
        case "long":
            return Numeric(NumberKind.long_, scalar.get!long);
        case "float":
            return Numeric(NumberKind.float_, 0, scalar.get!float);
        case "double":
            return Numeric(NumberKind.double_, 0, scalar.get!double);
        default:
            return Numeric.init;
        }
    }

    float asFloat() const pure nothrow @nogc
    {
        return kind >= NumberKind.float_ ? cast(float) realValue : cast(float) integer;
    }

    double asDouble() const pure nothrow @nogc
    {
        return kind >= NumberKind.float_ ? realValue : cast(double) integer;
    }

    Any pack() const pure nothrow @nogc
    {
        final switch (kind)
        {
        case NumberKind.other:
            return Any.init;
        case NumberKind.int_:
            return Any.of(cast(int) integer);
        case NumberKind.long_:
            return Any.of(integer);
        case NumberKind.float_:
            return Any.of(cast(float) realValue);
        case NumberKind.double_:
            return Any.of(realValue);
        }
    }
}

private Result!Numeric applyOperator(Op op, Numeric left, Numeric right) pure nothrow @nogc
{
    if (left.kind == NumberKind.other || right.kind == NumberKind.other)
        return Result!Numeric(Numeric.init, Error(Status.unsupported, "SpEL arithmetic requires numeric operands"));
    const kind = left.kind >= right.kind ? left.kind : right.kind;
    if (kind == NumberKind.double_)
        return Result!Numeric(Numeric(kind, 0, arithmetic(op, left.asDouble(), right.asDouble())));
    if (kind == NumberKind.float_)
        return Result!Numeric(Numeric(kind, 0, arithmetic(op, left.asFloat(), right.asFloat())));
    return integerArithmetic(op, kind, left.integer, right.integer);
}

private Result!Numeric integerArithmetic(Op op, NumberKind kind, long left, long right) pure nothrow @nogc
{
    if (op == Op.divide || op == Op.modulus)
    {
        if (right == 0)
            return Result!Numeric(Numeric.init, Error(Status.invalidArgument, "/ by zero"));
        if (left == long.min && right == -1)
            return Result!Numeric(Numeric(kind, op == Op.divide ? long.min : 0));
    }
    const value = arithmetic(op, left, right);
    return Result!Numeric(Numeric(kind, kind == NumberKind.int_ ? cast(int) value : value));
}

private T arithmetic(T)(Op op, T left, T right) pure nothrow @nogc
{
    final switch (op)
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
    case Op.literal:
        assert(0, "A literal has no arithmetic operator");
    }
}
