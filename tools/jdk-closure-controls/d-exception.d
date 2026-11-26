module timeout_probe;

@safe:

int main(string[] args)
{
    try
        throw new Exception(args.length > 1 ? args[1] : null);
    catch (Exception failure)
        return cast(int) failure.msg.length & 127;
}
