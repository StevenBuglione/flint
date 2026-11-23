/// Each declaration below triggers one Flint AOT diagnostic.
module bad.app;

import flint.beans.factory.annotation : Value;
import flint.boot.autoconfigure : FlintBootApplication;
import flint.cache.annotation : Cacheable;
import flint.context.annotation : Bean, Configuration, Profile;
import flint.data.repository : CrudRepository;
import flint.jakarta.annotation : PostConstruct;
import flint.scheduling.annotation : Async;
import flint.security.access.prepost : PreAuthorize;
import flint.stereotype : Component, Service;

@safe:

/// The application.
@FlintBootApplication
final class BadApplication
{
}

/// FLINT-E1105: two constructors, none @Autowired.
@Component
class TwoConstructors
{
    /// One.
    this(int a)
    {
    }

    /// Two.
    this(string b)
    {
    }
}

/// FLINT-E1106: nothing provides a Missing.
interface Missing
{
}

/// ditto
@Component
class NeedsMissing
{
    /// Injection point.
    this(Missing missing)
    {
    }
}

/// FLINT-E1107 and FLINT-E1102.
@Component
@Profile("a & b | c")
class Expressions
{
    /// SpEL that Flint AOT does not compile yet: a type reference.
    this(@Value("#{T(java.lang.Math).random()}") double random)
    {
    }
}

/// FLINT-E1108: a private lifecycle method.
@Component
class PrivateLifecycle
{
    @PostConstruct
    private void start()
    {
    }
}

/// FLINT-E1109: a final bean method in a proxied configuration.
@Configuration
class FinalBeanMethod
{
    /// Final.
    @Bean
    final PrivateLifecycle lifecycle()
    {
        return null;
    }
}

/// FLINT-E1112, FLINT-W1111 and FLINT-E1113.
@Service
class Advised
{
    @Cacheable("x")
    protected int hidden()
    {
        return 1;
    }

    /// Final, so not advised.
    @Cacheable("y")
    final int sealed()
    {
        return 2;
    }

    /// Returns a value.
    @Async
    int later()
    {
        return 3;
    }

    /// FLINT-E1107: a security function that does not exist.
    @PreAuthorize("frobnicate('x')")
    void guarded()
    {
    }
}

/// An entity.
struct Pet
{
    /// Key.
    long id;
    /// Name.
    string name;
    /// Nested.
    Owner owner;
}

/// Nested.
struct Owner
{
    /// Name.
    string name;
}

/// FLINT-E1101 and FLINT-E1114.
interface PetRepository : CrudRepository!(Pet, long)
{
    /// No such property.
    Pet[] findByColour(string colour);
    /// Nested path.
    Pet[] findByOwnerName(string name);
}

/// FLINT-E1110: a constructor-injection cycle.
@Component
class Chicken
{
    /// Needs an egg.
    this(Egg egg)
    {
    }
}

/// ditto
@Component
class Egg
{
    /// Needs a chicken.
    this(Chicken chicken)
    {
    }
}

/// FLINT-E1115: a bean that is not a class.
@Configuration
class ScalarBean
{
    /// An int.
    @Bean
    int answer()
    {
        return 42;
    }
}
