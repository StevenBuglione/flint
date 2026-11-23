// Misuse: a handler with an unsupported return type.
// expect: Items\.get: a handler returns Response, Error, Result!T or void, not `string`
module web_route;
import flint.engine.web : Get, PathVariable, RestController, ServerOptions, runApplication;
@RestController("/api/items") struct Items { @Get("/:id") string get(@PathVariable("id") ulong id) { return ""; } }
struct Application { Items items; }
int use() { Application app; ServerOptions server; return runApplication!Application(app, server); }
