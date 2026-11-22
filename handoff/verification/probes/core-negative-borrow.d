module escape_borrow;
import flint.arena;
const(ubyte)[] leaked;
void bad(ref RequestArena arena, Buffer b) @safe nothrow @nogc {
 arena.read(b, (scope const(ubyte)[] bytes) @safe nothrow @nogc { leaked=bytes; });
}
