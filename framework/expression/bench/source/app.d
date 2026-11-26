/// Exercises SpEL parsing and evaluation on a scalar literal.
module app;

import core.stdc.stdio : putchar;
import flint.expression.spel.standard : SpelExpressionParser;

@safe:

int main(string[] args)
{
    auto parser = new SpelExpressionParser;
    auto expression = parser.parseExpression(args.length > 1 ? "'Flint''s expression'" : "'Spring''s expression'");
    const value = expression.getValue().get!string;
    foreach (c; value)
        putchar(c);
    putchar('\n');
    return 0;
}
