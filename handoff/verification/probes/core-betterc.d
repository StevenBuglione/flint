module core_betterc;
import flint.arena;
import flint.serde;
import flint.validate;
@safe:
struct DTO { @Min(1) ulong id; @NotBlank Text name; }
extern(C) int coreProbe() nothrow @nogc {
 ubyte[4096] backing; scope RequestArena arena=RequestArena(backing[]);
 DTO dto; Violation[8] violations;
 auto report=validateIn(dto,arena,violations[]);
 auto json=encodeJson(dto,arena);
 arena.read(json.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc { });
 return report.valid ? 0 : 1;
}
