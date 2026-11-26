/// Selects a Thymeleaf mode and prints its public classification.
module app;

import core.stdc.stdio : putchar;
import flint.thymeleaf.templatemode : TemplateMode;

@safe:

int main(string[] args)
{
    const mode = TemplateMode.valueOf(args.length > 1 ? "TEXT" : "HTML");
    foreach (c; mode.name())
        putchar(c);
    putchar(' ');
    foreach (c; mode.isMarkup() ? "markup" : mode.isText() ? "text" : "raw")
        putchar(c);
    putchar(' ');
    foreach (c; mode.isCaseSensitive() ? "sensitive" : "insensitive")
        putchar(c);
    putchar('\n');
    return 0;
}
