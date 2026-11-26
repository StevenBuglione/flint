module app;

import flint.java.time.year : Year;

@safe:

int main(string[] args)
{
    const text = args.length > 1 ? args[1] : "2000";
    const rendered = Year.parse(text).toString();
    return rendered[0] + rendered[$ - 1];
}
