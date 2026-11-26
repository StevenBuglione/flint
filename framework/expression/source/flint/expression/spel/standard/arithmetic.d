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
 * OpAnd.java, OpOr.java, OperatorNot.java, Ternary.java and Elvis.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard.arithmetic;

import core.stdc.math : pow;
import flint.arena : Error, Result, Status;
import flint.engine.aot.any : Any;
import flint.engine.aot.text : decodeUtf8;
import flint.expression.spel : SpelMessage;
import flint.expression.spel.standard.literal : LiteralName, LiteralParser, literalName, startsIdentifier;
import flint.expression.spel.standard.property : PropertySeparator, PropertyStep, readSeparator;
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
    bool readsRoot;
    private immutable(PropertyStep[])[] propertyPaths;
    private immutable(Instruction[])[] indexPlans;
    private size_t instructionCount;

    bool hasProperties() const pure nothrow @nogc
    {
        return propertyPaths.length != 0;
    }

    Result!Any evaluate(Read, ReadStep)(Any root, scope Read read, scope ReadStep readStep)
    {
        if (variable !is null)
            return Result!Any(lookup(root, variable, read));
        if (instructions.length == 0)
            return Result!Any(constant);
        if (instructions.length == 1 && instructions[0].op == Op.property && indexPlans.length == 0)
            return evaluateInStack(root, read, readStep, null);
        if (instructionCount < 2 * shortStack)
        {
            Scalar[shortStack] stack;
            return evaluateInStack(root, read, readStep, stack);
        }
        Scalar[maxStack] stack;
        return evaluateInStack(root, read, readStep, stack);
    }

private:
    enum shortStack = 16;

    // Array lookups suspend a path on the frame stack. Every program borrows the same scalar stack.
    pragma(inline, false) Result!Any evaluateInStack(Read, ReadStep)(ref Any root, scope Read read,
            scope ReadStep readStep, scope Scalar[] stack)
    {
        if (indexPlans.length == 0)
        {
            EvaluationFrame[1] frames;
            return run(root, read, readStep, stack, frames);
        }
        if (stack.length == shortStack)
        {
            EvaluationFrame[2 * shortStack] frames;
            return run(root, read, readStep, stack, frames);
        }
        EvaluationFrame[maxNesting + 1] frames;
        return run(root, read, readStep, stack, frames);
    }

    pragma(inline, false) Result!Any run(Read, ReadStep)(ref Any root, scope Read read,
            scope ReadStep readStep, scope Scalar[] stack, scope EvaluationFrame[] frames)
    {
        size_t level;
        frames[0].program = instructions;
        bool resumePath;
        Error error;
        for (;;)
        {
            auto frame = &frames[level];
            if (resumePath && runPath(*frame, readStep))
            {
                const step = &frame.path[0];
                frames[++level] = EvaluationFrame(indexPlans[step.index], frame.base + frame.depth);
                resumePath = false;
                continue;
            }

            const(Instruction)* instruction;
            if (resumePath && frame.program.length == 1)
                frame.value = frame.target;
            else
            {
                if (resumePath)
                    push(*frame, stack, frame.target);
                instruction = advance(frame.program, stack[frame.base .. $], frame.depth,
                        frame.next, frame.value, error);
            }

            if (instruction !is null)
            {
                auto target = instruction.value.text is null ? lookup(root, instruction.variable,
                        read) : Any.of(instruction.value.text);
                resumePath = instruction.op == Op.property;
                if (resumePath)
                {
                    frame.target = target;
                    frame.path = propertyPaths[instruction.jump];
                }
                else
                    push(*frame, stack, target);
                continue;
            }

            if (level == 0 || error.code != Status.ok)
                return Result!Any(frame.value, error);
            auto parent = &frames[--level];
            readStep(parent.target, parent.path[0], frame.value);
            parent.path = parent.path[1 .. $];
            resumePath = true;
        }
    }

    // Return with the index step still at the head of the path when a child program must run.
    static bool runPath(ReadStep)(ref EvaluationFrame frame, scope ReadStep readStep)
    {
        const Any noIndex;
        while (frame.path.length)
        {
            const step = &frame.path[0];
            if (step.name is null && !frame.target.isNull())
                return true;
            readStep(frame.target, *step, noIndex);
            frame.path = frame.path[1 .. $];
        }
        return false;
    }

    static Any lookup(Read)(ref Any root, string name, scope Read read)
    {
        return name is null || isRootReference(name) ? root : read(name);
    }

    static void push(ref EvaluationFrame frame, scope Scalar[] stack, Any value) nothrow @nogc
    {
        const scalar = Scalar.from(value);
        // Only the bottom operand can become the result. Keep its original box when it is opaque.
        if (scalar.kind == ValueKind.other && frame.depth == 0)
            frame.value = value;
        stack[frame.base + frame.depth++] = scalar;
    }

    static const(Instruction)* advance(return scope const(Instruction)[] program, scope Scalar[] stack,
            ref size_t sp, ref size_t pc, ref Any value, ref Error failure) nothrow @nogc
    {
        for (; pc < program.length;)
        {
            const instruction = &program[pc++];
            if (instruction.op == Op.literal)
            {
                stack[sp++] = instruction.value;
                continue;
            }
            if (instruction.op == Op.variable || instruction.op == Op.property)
                return instruction;
            if (instruction.op == Op.elvis || instruction.op == Op.jump)
            {
                stepJump(*instruction, stack[sp - 1], sp, pc);
                continue;
            }
            if (instruction.op >= Op.positive)
            {
                const error = instruction.op < Op.and_ ? stepSign(*instruction,
                        stack[sp - 1]) : stepBoolean(*instruction, stack[sp - 1], sp, pc);
                if (error.code != Status.ok)
                {
                    failure = error;
                    return null;
                }
                continue;
            }
            const right = stack[--sp];
            const applied = applyOperator(instruction.op, stack[sp - 1], right);
            if (!applied.ok())
            {
                failure = Error(applied.error.code, applied.error.message, instruction.position);
                return null;
            }
            stack[sp - 1] = applied.value;
        }
        if (stack[0].kind != ValueKind.other)
            value = stack[0].pack();
        return null;
    }
}

ArithmeticExpression parseArithmetic(string source)
{
    ArithmeticParser parser = ArithmeticParser(LiteralParser(source));
    parser.reader.skipWhitespace();
    if (parser.reader.position == source.length)
        throw new IllegalArgumentException("'expressionString' must not be null or blank");
    parser.conditional(0);
    const end = parser.reader.position;
    if (end < source.length)
        throw parser.reader.errorAt(end, SpelMessage.MORE_INPUT, source[end .. $]);
    if (parser.instructions.length == 0)
        return ArithmeticExpression(parser.firstLiteral, null, parser.firstVariable, parser.readsRoot);
    auto expression = ArithmeticExpression(Any.init, parser.instructions.idup, null,
            parser.readsRoot, parser.propertyPaths.idup, parser.indexPlans.idup);
    // A suspended lookup has yet to push its value. Counting all plans' instructions bounds the small stack.
    expression.instructionCount = expression.instructions.length;
    foreach (ref index; expression.indexPlans)
        expression.instructionCount += index.length;
    return expression;
}

private enum Op : ubyte
{
    literal,
    variable,
    property,
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
    elvis,
    jump,
    positive,
    negative,
    and_,
    or_,
    not_,
    requireBoolean,
    testCondition,
}

private struct Instruction
{
    Op op;
    size_t position;
    Scalar value;
    size_t jump;
    string variable;
}

private struct EvaluationFrame
{
    immutable(Instruction)[] program;
    size_t base;
    size_t depth;
    size_t next;
    Any value;
    immutable(PropertyStep)[] path;
    Any target;
}

private struct ArithmeticParser
{
    LiteralParser reader;
    Instruction[] instructions;
    Any firstLiteral;
    size_t firstPosition = size_t.max;
    string firstVariable;
    bool readsRoot;
    immutable(PropertyStep)[][] propertyPaths;
    immutable(Instruction)[][] indexPlans;

    size_t conditional(uint nesting)
    {
        reader.skipWhitespace();
        const atStart = reader.position;
        size_t left = atStart;
        if (atConditional())
            operand(atStart, Any.init);
        else
            left = parse(orPrecedence, nesting);
        if (!atConditional())
            return left;

        checkNesting(nesting);
        const position = reader.position++;
        emitFirstOperand();
        if (reader.peek == ':')
            fallback(nesting + 1, position);
        else
            ternary(nesting + 1, left, position);
        return position;
    }

    bool atConditional() const pure nothrow @nogc
    {
        if (reader.peek != '?')
            return false;
        const after = reader.position + 1;
        return after == reader.text.length || reader.text[after] != '.';
    }

    void ternary(uint nesting, size_t left, size_t position)
    {
        const whenFalse = instructions.length;
        instructions ~= Instruction(Op.testCondition, left);
        conditional(nesting);
        if (reader.peek != ':')
            throw reader.errorAt(reader.position, SpelMessage.OOD);
        ++reader.position;
        const end = instructions.length;
        instructions ~= Instruction(Op.jump, position);
        instructions[whenFalse].jump = instructions.length;
        conditional(nesting);
        instructions[end].jump = instructions.length;
    }

    void fallback(uint nesting, size_t position)
    {
        ++reader.position;
        const end = instructions.length;
        instructions ~= Instruction(Op.elvis, position);
        reader.skipWhitespace();
        if (reader.position == reader.text.length || reader.peek == ')' || reader.peek == ':')
            operand(reader.position, Any.init);
        else
            conditional(nesting);
        instructions[end].jump = instructions.length;
    }

    size_t parse(ubyte minimumPrecedence, uint nesting)
    {
        size_t left = parsePower(nesting);
        ubyte maximumPrecedence = ubyte.max;
        while (true)
        {
            reader.skipWhitespace();
            const position = reader.position;
            const token = operatorToken(reader.text[position .. $]);
            if (token.precedence < minimumPrecedence || token.precedence > maximumPrecedence)
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
        if (reader.peek != '^')
            return left;
        const position = reader.position++;
        primary(nesting);
        instructions ~= Instruction(Op.power, position);
        return position;
    }

    void logical(Op op, size_t left, ubyte rhsPrecedence, uint nesting)
    {
        emitFirstOperand();
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
            emitFirstOperand();
            instructions ~= Instruction(Op.not_, operand);
            return position;
        }
        if (readSign(nesting))
            return position;
        if (reader.peek == '(')
        {
            checkNesting(nesting);
            ++reader.position;
            const inner = conditional(nesting + 1);
            if (reader.peek != ')')
                throw reader.errorAt(reader.position, SpelMessage.OOD);
            ++reader.position;
            return inner;
        }
        if (reader.peek == '#')
        {
            const name = readVariableName();
            readsRoot |= isRootReference(name);
            const separator = readSeparator(reader);
            if (separator != PropertySeparator.absent)
                property(position, name, readStep(separator == PropertySeparator.safeDot, nesting), nesting);
            else
                operand(position, Any.init, name);
        }
        else if (reader.peek == '[')
        {
            readsRoot = true;
            property(position, null, readStep(false, nesting), nesting);
        }
        else
        {
            const name = reader.readIdentifierName();
            if (name !is null && literalName(name) == LiteralName.other)
            {
                readsRoot = true;
                property(position, null, PropertyStep(name, position, false), nesting);
            }
            else
            {
                reader.position = position;
                auto value = reader.readLiteral();
                const afterLiteral = reader.position;
                const separator = readSeparator(reader);
                if (reader.peek == '[' && value.typeName() == "string")
                    property(position, null, readStep(separator == PropertySeparator.safeDot,
                            nesting), nesting, value.get!string);
                else
                {
                    reader.position = afterLiteral;
                    operand(position, value);
                }
            }
        }
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
        emitFirstOperand();
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
        const name = reader.readIdentifierName();
        if (name is null)
            throw reader.errorAt(reader.position, SpelMessage.OOD);
        return name;
    }

    void operand(size_t position, Any value, string variable = null)
    {
        if (firstPosition == size_t.max && instructions.length == 0)
        {
            firstLiteral = value;
            firstPosition = position;
            firstVariable = variable;
            return;
        }
        emitFirstOperand();
        emitOperand(position, value, variable);
    }

    void emitFirstOperand()
    {
        if (instructions.length == 0 && firstPosition != size_t.max)
            emitOperand(firstPosition, firstLiteral, firstVariable);
    }

    void emitOperand(size_t position, const ref Any value, string variable)
    {
        if (variable is null)
            instructions ~= Instruction(Op.literal, position, Scalar.from(value));
        else
            instructions ~= Instruction(Op.variable, position, Scalar.init, 0, variable);
    }

    PropertyStep readStep(bool nullSafe, uint nesting)
    {
        reader.skipWhitespace();
        const position = reader.position;
        if (reader.peek != '[')
        {
            const name = reader.readIdentifierName();
            if (name is null)
                throw reader.errorAt(position, SpelMessage.OOD);
            return PropertyStep(name, position, nullSafe);
        }
        checkNesting(nesting);
        ++reader.position;
        ArithmeticParser index = ArithmeticParser(reader);
        index.indexPlans = indexPlans;
        index.propertyPaths = propertyPaths;
        index.conditional(nesting + 1);
        index.emitFirstOperand();
        reader.position = index.reader.position;
        if (reader.peek != ']')
            throw reader.errorAt(reader.position, SpelMessage.OOD);
        ++reader.position;
        indexPlans = index.indexPlans;
        propertyPaths = index.propertyPaths;
        // Every child is stored once in the outer plan's table. Source length bounds this offset.
        const slot = cast(uint) indexPlans.length;
        indexPlans ~= index.instructions.idup;
        return PropertyStep(null, position, nullSafe, slot);
    }

    void property(size_t position, string target, PropertyStep first, uint nesting, string literal = null)
    {
        emitFirstOperand();
        auto steps = [first];
        auto separator = readSeparator(reader);
        while (separator != PropertySeparator.absent)
        {
            steps ~= readStep(separator == PropertySeparator.safeDot, nesting);
            separator = readSeparator(reader);
        }
        Scalar receiver;
        receiver.text = literal;
        instructions ~= Instruction(Op.property, position, receiver, propertyPaths.length, target);
        propertyPaths ~= steps.idup;
    }
}

bool isRootReference(string name) pure nothrow @nogc
{
    return name == "root" || name == "this";
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
    byte_,
    short_,
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

    static Scalar from(const ref Any scalar) pure nothrow @nogc
    {
        if (scalar.isNull())
            return Scalar(ValueKind.null_);
        const type = scalar.typeName();
        if (type == "bool")
            return fromNumber!bool(scalar, ValueKind.bool_);
        if (type == "string")
        {
            string decoded;
            return scalar.tryGet(decoded) ? Scalar(ValueKind.string_, 0, 0, decoded) : Scalar.init;
        }
        return fromNumeric(scalar, type);
    }

    private static Scalar fromNumeric(const ref Any scalar, string type) pure nothrow @nogc
    {
        switch (type)
        {
        case "byte":
            return fromNumber!byte(scalar, ValueKind.byte_);
        case "short":
            return fromNumber!short(scalar, ValueKind.short_);
        case "int":
            return fromNumber!int(scalar, ValueKind.int_);
        case "long":
            return fromNumber!long(scalar, ValueKind.long_);
        case "float":
            return fromNumber!float(scalar, ValueKind.float_);
        case "double":
            return fromNumber!double(scalar, ValueKind.double_);
        default:
            return Scalar.init;
        }
    }

    private static Scalar fromNumber(T)(const ref Any scalar, ValueKind kind) pure nothrow @nogc
    {
        T value;
        if (!scalar.tryGet(value))
            return Scalar.init;
        static if (is(T == double) || is(T == float))
            return Scalar(kind, 0, value);
        else
            return Scalar(kind, value);
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
        case ValueKind.byte_:
            return Any.of(cast(byte) integer);
        case ValueKind.short_:
            return Any.of(cast(short) integer);
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
    const widest = left.kind >= right.kind ? left.kind : right.kind;
    const kind = widest >= ValueKind.int_ ? widest : ValueKind.int_;
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

private void stepJump(const ref Instruction step, const ref Scalar top, ref size_t sp, ref size_t pc) pure nothrow @nogc
{
    if (step.op == Op.elvis && (top.kind == ValueKind.null_ || (top.kind == ValueKind.string_ && top.text.length == 0)))
        --sp;
    else
        pc = step.jump;
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
    case Op.testCondition:
        --used;
        if (!truth)
            pc = step.jump;
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
    static immutable string[] names = [
        "java.lang.Object", "java.lang.Byte", "java.lang.Short", "java.lang.Integer", "java.lang.Long",
        "java.lang.Float", "java.lang.Double", "null", "java.lang.Boolean", "java.lang.String"
    ];
    return names[kind];
}

private bool isNumber(ValueKind kind) pure nothrow @nogc
{
    return kind >= ValueKind.byte_ && kind <= ValueKind.double_;
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
