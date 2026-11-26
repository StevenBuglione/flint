module app;

import flint.java.text.simpledateformat : SimpleDateFormat;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "yyyy-MM-dd";
    return cast(int)((new SimpleDateFormat(arg)).toPattern().length) & 127;
}
