module app;

import flint.java.util.function_.unaryoperator : UnaryOperator;

@safe:

int main(string[] args)
{
    const operand = cast(int) args.length;
    return UnaryOperator!int.identity().apply(operand) & 127;
}
