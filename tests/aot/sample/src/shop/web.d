/// A REST controller, as in gs-rest-service.
module shop.web;

import flint.web.bind.annotation : ExceptionHandler, GetMapping, PathVariable, RequestMapping, RequestParam,
    RestController;
import shop.owners : OwnerService;

@safe:

/// The response body.
struct Greeting
{
    /// Sequence number.
    long id;
    /// Greeting text.
    string content;
}

/// Greets owners.
@RestController @RequestMapping("/owners") class OwnerController
{
    private OwnerService owners;

    /// Constructor injection.
    this(OwnerService owners)
    {
        this.owners = owners;
    }

    /// GET /owners/{id}?greeting=...
    @GetMapping("/{id}") Greeting greeting(@PathVariable long id,
            @RequestParam(value: "greeting", defaultValue: "Hello") string greeting)
    {
        return Greeting(id, greeting ~ ", " ~ owners.findName(id));
    }

    /// Answers a failed lookup; the second argument is resolved by type.
    @ExceptionHandler Greeting failed(Exception error, string path)
    {
        return Greeting(0, error.msg ~ " at " ~ path);
    }
}
