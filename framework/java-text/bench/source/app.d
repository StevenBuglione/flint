module app;

import flint.java.text : MessageFormat, SimpleDateFormat;

@safe:

int main(string[] args)
{
    const message = args.length > 1 ? args[1] : "Hi {0}";
    const date = args.length > 2 ? args[2] : "yyyy-MM-dd";
    const messageLength = (new MessageFormat(message)).toPattern().length;
    const dateLength = (new SimpleDateFormat(date)).toPattern().length;
    return cast(int)((messageLength + dateLength) & 127);
}
