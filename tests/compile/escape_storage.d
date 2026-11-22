module escape_storage;
import flint.arena;
RequestArena bad() @safe nothrow @nogc {
 ubyte[32] backing;
 return RequestArena(backing[]);
}
