module flint_tool.project.generators_test;

import flint_tool.commands.generate : withDependencies;
import flint_tool.project.generators : agentsGuide, generate, plural, snakeCase, validTypeName;
import flint.test : expect;

@safe:

@("names become features, resources and module paths")
unittest
{
    expect(snakeCase("OrderItem")).toEqual("order_item");
    expect(plural("order")).toEqual("orders");
    expect(plural("category")).toEqual("categories");
    expect(plural("box")).toEqual("boxes");
    expect(validTypeName("Order")).toEqual(true);
    expect(validTypeName("order")).toEqual(false);
    expect(validTypeName("Or-der")).toEqual(false);
}

@("generators write package-by-feature files and name the packages they need")
unittest
{
    import std.algorithm.searching : canFind;

    const entity = generate("entity", "OrderItem", "shop", 1, null);
    expect(entity.files[0].path).toEqual("src/shop/order_item/order_item.d");
    expect(entity.files[0].content.canFind("module shop.order_item.order_item;")).toEqual(true);
    expect(entity.files[0].content.canFind("@Table(\"order_items\")")).toEqual(true);
    expect(entity.packages).toEqual(["arena", "engine-data", "serde", "validate"]);
    const migration = generate("migration", "OrderItem", "shop", 12, null);
    expect(migration.files[0].path).toEqual("resources/migrations/V000012__order_item.sql");
    const plain = generate("service", "Mailer", "shop", 1, null);
    expect(plain.files[0].content.canFind("Repository")).toEqual(false);
    const wired = generate("service", "Order", "shop", 1, ["src/shop/order/repository.d"]);
    expect(wired.files[0].content.canFind("this(OrderRepository repository)")).toEqual(true);
    expect(agentsGuide("shop", "shop", "executable").canFind("module shop.order.service;")).toEqual(true);
}

@("dependencies are added to an existing or a new [dependencies] table")
unittest
{
    expect(withDependencies("[project]\n[dependencies]\n\"flint:log\" = {}\n", ["flint:engine-web"])).toEqual(
            "[project]\n[dependencies]\n\"flint:engine-web\" = {}\n\"flint:log\" = {}\n");
    expect(withDependencies("[project]\nname = \"x\"\n", ["flint:engine-web"])).toEqual(
            "[project]\nname = \"x\"\n\n[dependencies]\n\"flint:engine-web\" = {}\n");
}
