// A 24-byte struct passed by value to a recursive call: the copy's destination
// register must not reuse the register holding the source pointer.
struct R { void* a; void* b; void* c; alias a this; }
struct Node { Node* left, right; R e; uint pri; }
__gshared Node[8] pool;
__gshared int np;

Node* ins(Node* n, R e)
{
    if (!n) { auto x = &pool[np++]; x.e = e; return x; }
    else if (e < n.e) n.left = ins(n.left, e);
    else if (e > n.e) n.right = ins(n.right, e);
    return n;
}

int main()
{
    __gshared ubyte[16] b1, b2, b3;
    Node* root;
    root = ins(root, R(b2.ptr, b2.ptr + 16, null));
    root = ins(root, R(b1.ptr, b1.ptr + 16, null));
    root = ins(root, R(b3.ptr, b3.ptr + 16, null));
    foreach (i; 0 .. np)
        if (pool[i].e.b != pool[i].e.a + 16 || pool[i].e.c !is null)
            return 1;
    return 0;
}
