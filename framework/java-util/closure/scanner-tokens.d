/// Link proof for the Java String Scanner leaf.
module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.scanner : Scanner;

@safe:

int main(string[] args)
{
    auto scanner = new Scanner("  alpha beta\n gamma\r\ndelta  ");
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
