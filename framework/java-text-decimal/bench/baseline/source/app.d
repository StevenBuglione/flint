module app;

@safe:

int main(string[] args)
{
    const pattern = args.length > 1 ? args[1] : "#,##0.00";
    return cast(int)((pattern.length + 1 + 7) & 127);
}
