// Misuse: a @PathVariable naming no route capture.
// expect: @PathVariable does not name a capture on Items\.get: name
module web_path_variable;
@safe:
import flint.arena : Result;
import flint.engine.web : Get, PathVariable, RequestContext, RestController, ServerOptions, runApplication;
@RestController("/api/items") struct Items { @Get("/:id") Result!string get(@PathVariable("name") ulong id, ref scope RequestContext context) nothrow @nogc { return Result!string("x"); } }
struct Application { Items items; }
int use() { Application app; ServerOptions server; return runApplication!Application(app, server); }
