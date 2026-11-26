module app;

@safe:

int main(string[] args)
{
    const message = args.length > 1 ? args[1] : "Hi {0}";
    const date = args.length > 2 ? args[2] : "yyyy-MM-dd";
    return cast(int)((message.length + date.length) & 127);
}
