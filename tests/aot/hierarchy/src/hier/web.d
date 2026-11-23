/// A controller whose class-level mapping is on an interface and one of whose handlers is in a base class.
module hier.web;

import flint.web.bind.annotation : GetMapping, RequestMapping, RestController;

@safe:

/// The class-level `@RequestMapping` applies to the implementing controller, as Spring MVC finds it through the
/// type hierarchy; so does the method-level `@GetMapping`.
@RequestMapping("/api") interface PingApi
{
    /// GET /api/ping
    @GetMapping("/ping") string ping();
}

/// Handler methods a subclass inherits are handlers too.
abstract class BaseController
{
    /// GET /api/version
    @GetMapping("/version") string version_()
    {
        return "1";
    }
}

/// Mapped through its interface and its base class only.
@RestController class PingController : BaseController, PingApi
{
    /// Implements `PingApi.ping`.
    string ping()
    {
        return "pong";
    }
}
