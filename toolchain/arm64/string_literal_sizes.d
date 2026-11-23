// String literals of different character sizes with the same bytes get their own
// symbols: "", ""w and ""d are each terminated by a zero of their character size.
size_t len(C)(const(C)* p) { size_t n; while (p[n]) ++n; return n; }

int main()
{
    // the char literals come first, so a shared symbol would have a 1 byte terminator
    immutable(char)* c0 = "".ptr;
    immutable(char)* c1 = "a\0".ptr;          // same bytes as "a"w
    immutable(wchar)* w0 = ""w.ptr;
    immutable(wchar)* w1 = "a"w.ptr;
    immutable(dchar)* d0 = ""d.ptr;
    immutable(char)* foo = "foo".ptr;         // non-zero bytes after the char literals
    if (len(c0) != 0 || len(c1) != 1 || foo[0] != 'f') return 1;
    if (len(w0) != 0) return 2;
    if (len(w1) != 1) return 3;
    if (len(d0) != 0) return 4;
    return 0;
}
