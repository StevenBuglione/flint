/// Link proof for the Java String Scanner leaf.
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.scanner : Scanner;

@safe:

int main(string[] args)
{
    const source = args.length > 1 ? args[1] : "  alpha beta\n gamma\r\ndelta  ";
    auto scanner = new Scanner(source);
    int count;
    while (scanner.hasNext())
    {
        foreach (character; scanner.next())
            fputc(character, stdout);
        count++;
    }
    while (scanner.hasNextLine())
    {
        foreach (character; scanner.nextLine())
            fputc(character, stdout);
        count++;
    }
    scanner.close();
    return count & 127;
}
