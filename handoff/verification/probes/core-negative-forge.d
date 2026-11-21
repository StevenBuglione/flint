module negative_forge;
import flint.arena : Buffer;
Buffer fabricate() @safe nothrow @nogc { return Buffer(1,1,0,10); }
