module positive;
import flint.arena;
import flint.conc;
import flint.engine.di;
import flint.serde;
import flint.serde.owned;
import flint.validate;
import flint.config;
import flint.log;
import flint.test;
@safe:
@ConfigurationProperties("app") struct Config { @Required ushort port; }
@Service final class Worker { this() {} }
struct DTO { @Min(1) ulong id; @NotBlank Text name; }
interface Repository { int value() @safe; }
void startup() {
 ConfigOptions options; auto c=load!Config(options);
 AppContext!(Worker) context; auto e=context.initialize();
 auto worker=context.get!Worker();
 auto logger=Logger.create(LogOptions.init); logger.value.info("hello");
 auto object=deserialize!Config("{\"port\":8080}");
 auto m=Mock!Repository.create(); auto i=m.instance();
 expect(2).toEqual(2);
}
void hotPath() nothrow @nogc {
 ubyte[4096] backing; scope RequestArena arena=RequestArena(backing[]);
 DTO dto; Violation[8] violations;
 auto report=validateIn(dto,arena,violations[]);
 auto json=encodeJson(dto,arena);
 arena.read(json.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc { assert(bytes.length<=4096); });
 auto err=decodeInto(cast(const(ubyte)[])"{\"id\":1,\"name\":\"Steve\"}",dto,arena);
}
