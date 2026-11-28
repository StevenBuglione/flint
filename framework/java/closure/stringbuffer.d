module stringbuffer_probe;

import flint.java.lang.stringbuffer : StringBuffer;

@safe:

pragma(inline, false) private int build(int n)
{
    auto buffer = new StringBuffer("ab");
    buffer.append("c\U0001F680").append(cast(wchar) 'd');
    return buffer.length() + cast(int) buffer.toString().length + n;
}

int main(string[] args)
{
    return build(cast(int) args.length) & 7;
}
