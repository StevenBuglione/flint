/// SpEL in @Value, compiled to D at build time.
module shop.pricing;

import flint.beans.factory.annotation : Value;
import flint.stereotype : Component;

@safe:

/// Values computed from beans, placeholders and literals.
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
}
