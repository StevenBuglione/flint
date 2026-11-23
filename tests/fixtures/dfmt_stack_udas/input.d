module stack_udas;

@safe:

@RestController @RequestMapping("/api") class GreetingController
{
    @Autowired Service service;
    @Value("${server.port}") auto port = 8080;
    @Value("${limit}") enum limit = 3;

    @Autowired this(Service service) { this.service = service; }

    @PreDestroy ~this() { }

    @GetMapping("/greeting/{id}") @ResponseBody Greeting greeting(@PathVariable("id") long id, @RequestParam("name") string name) { return Greeting.init; }

    @Bean public Service bean() { return service; }
    @Transactional @safe void save() { }
    @Foo!int @Bar!(int, "x")("y") int templated;
    @Transactional(readOnly: true) void readOnly() { }
    @ConditionalOnProperty(name: ["flint.datasource.url", "flint.datasource.driver-class-name"], havingValue: "true") void conditional() { }
    Greeting nogc(@PathVariable("id") long id)nothrow @nogc { return Greeting.init; }
    Greeting constant(@PathVariable("id") long id) const { return Greeting.init; }
    Greeting named(@RequestParam(value : "name", defaultValue : "World") string name) { return Greeting.init; }

    // Built-in attributes stay inline.
    @safe void safe() { }
    @trusted @nogc nothrow pure int pureFunction() const scope { return 1; }
    @property int property() const { return 1; }
    @disable this(this);

    // A run of user-defined attributes stops at the first other attribute or storage class.
    public @Bean Service afterVisibility() { return service; }
    static @Foo int afterStatic;
    @safe @Foo void afterBuiltin() { }
    deprecated("old") @Foo int afterDeprecated;

    // Expression UDAs, attribute blocks and labels keep their layout.
    @("label") int labelled;
    @Foo { int inBlock; }
@Foo:
    int afterLabel;

    // A comment between the attribute and the declaration keeps its place.
    @Foo // why
    int commented;
    @Foo /* inline */ int blockComment;
}

@Component struct Repository { @Id @Column("id") long id; @Column("name") string name; }
@Configuration interface Settings { @GetMapping("/a") string a(); }
@Foo enum Color { red }
@Foo union Union { int a; }
@Foo template Template() { }
@Foo mixin template Mixin() { }

version (unittest)
{
    @Foo struct InVersion { }
}

void statements()
{
    // Local variables are statements: their attributes stay inline. A local aggregate's fields stack.
    @Foo int local = 1;
    struct Local { @Field int field; }
    auto lambda = () { @Bar int y; return y; };
}

@("name") unittest
{
    @Foo struct InTest { @Bar int x; }
}
