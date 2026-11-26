/// SpEL in @Value, compiled to D at build time.
module shop.pricing;

import flint.beans.factory.annotation : Value;
import flint.context.event : EventListener;
import flint.core.annotation : ClassRef;
import flint.stereotype : Component;

@safe:

/// Values computed from beans, placeholders and literals.
/// Price events.
abstract class PriceEvent
{
    /// What happened.
    string label;

    /// An event labelled `label`.
    this(string label)
    {
        this.label = label;
    }
}

/// A price went up.
final class PriceRaised : PriceEvent
{
    /// ditto
    this(string label)
    {
        super(label);
    }
}

/// A price went down.
final class PriceCut : PriceEvent
{
    /// ditto
    this(string label)
    {
        super(label);
    }
}

@Component class Pricing
{
    /// `@clock.now()` is 42 in the sample.
    long doubled;
    /// Text around expressions.
    string label;
    /// Boolean logic over a placeholder and a bean.
    bool premium;

    /// Constructor injection of SpEL values.
    this(@Value("#{@clock.now() * 2 + ${shop.bonus:1}}") long doubled,
            @Value("Shop #{'${shop.name:Flint}'.toUpperCase()} is #{@clock.now() > 40 ? 'open' : 'closed'}")
            string label, @Value("#{${shop.premium:false} or @clock.now() == 42}") bool premium)
    {
        this.doubled = doubled;
        this.label = label;
        this.premium = premium;
    }

    /// A listener with a result: the runtime publishes it as a reply (invokeForResult).
    @EventListener string onGreeting(string text)
    {
        return "re: " ~ text;
    }

    /// Price events seen by the listeners below.
    string[] priceEvents;

    /// `@EventListener(classes)` without a parameter: one listener per class (Spring's `@EventListener(X.class)`).
    @EventListener(classes: [ClassRef("shop.pricing.PriceRaised"), ClassRef("shop.pricing.PriceCut")])
    void onPriceEvent()
    {
        priceEvents ~= "any";
    }

    /// `@EventListener(classes)` with a parameter of their base type.
    @EventListener(classes: [ClassRef("shop.pricing.PriceCut")]) void onPriceCut(PriceEvent event)
    {
        priceEvents ~= "cut " ~ event.label;
    }

    /// Large numbers only: the condition compiles to `context.argument(0).get!(long)() > cast(long) (10)`.
    @EventListener(condition: "#event > 10") void onNumber(long event)
    {
        doubled = event;
    }
}
