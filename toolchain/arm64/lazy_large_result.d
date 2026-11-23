// A lazy parameter is a delegate passed by value, even when its expression's type is
// larger than 16 bytes (which AArch64 passes by reference).
struct Big { int[] a; size_t i; }
Big mk() { Big b; b.i = 7; return b; }

int take(T)(lazy T expression, string msg = null, string file = __FILE__, size_t line = 10)
{
    auto v = expression();
    return cast(int)(v.i + msg.length + line);
}

int main()
{
    return take(mk()) == 17 && take(mk(), "ab") == 19 ? 0 : 1;
}
