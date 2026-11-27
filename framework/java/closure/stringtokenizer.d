module app;

import flint.java.util.stringtokenizer : StringTokenizer;

@safe:

int main(string[] args)
{
    const text = args.length > 1 ? args[1] : "a b\U0001F600c";
    const delimiters = args.length > 2 ? args[2] : " \U0001F600";
    auto tokens = new StringTokenizer(text, delimiters);
    int count = tokens.countTokens();
    while (tokens.hasMoreElements())
        count += cast(int) tokens.nextToken().length;
    if (args.length > 3)
        count += cast(int) tokens.nextToken(args[3]).length;
    return count;
}
