module app;

import flint.java.time.format : DateTimeFormatter;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "uuuu-MM-dd";
    return cast(int)(DateTimeFormatter.ofPattern(arg).toString().length) & 127;
}
