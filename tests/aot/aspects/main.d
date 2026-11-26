module aspects_main;

import aot_context : AotContext;
import aspects.app : Journal, OwnerService;
import flint.engine.aot.registry : installedRegistry;
import std.array : join;

@safe:

void main()
{
    auto context = new AotContext(null, null);
    installedRegistry()(context);
    context.refresh();
    scope (exit)
        context.close();
    auto service = cast(OwnerService) context.getBean("ownerService");
    auto journal = cast(Journal) context.getBean("journal");

    assert(service.update(5) == 6);
    service.rename();
    service.renameFromInside();
    service.read();
    assert(journal.events == [
        "ordered-before-update", "transaction-start", "before-update", "update", "transaction-end",
        "before-rename", "rename", "rename", "read",
    ], journal.events.join(", "));
}
