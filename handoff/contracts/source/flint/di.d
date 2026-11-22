/// Public API contract; declarations are not runtime implementations.
module flint.di;
import flint.arena : Error;

@safe:
struct Service
{
}

struct Repository
{
}

struct Component
{
}

struct Singleton
{
}

struct Inject
{
}

struct Named
{
    string value;
}

struct PostConstruct
{
}

struct PreDestroy
{
}

struct Bind(Contract, Implementation)
{
    alias ContractType = Contract;
    alias ImplementationType = Implementation;
}
/// Bindings are explicit types; no module/classpath scan occurs.
struct BeanRegistrar(Bindings...)
{
}
/// Members expose concrete type-directed access to startup-created beans.
struct AppContext(Beans...)
{
    private void* state;
    @disable this(this);
    Error provide(T)(T value);
    Error initialize();
    T get(T)();
    void shutdown() nothrow;
}
