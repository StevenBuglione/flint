module app;
import flint.java.math.bigdecimal : BigDecimal;

@safe:
int main(string[] args)
{
    const text = args.length > 1 ? args[1] : "-１２３４５６７８９０１２３４５６７８９０.125";
    auto decimal = new BigDecimal(text);
    const bool valid = decimal.precision() > 0 && decimal.scale() < int.max && decimal.signum() != 2;
    const canonical = decimal.toString();
    if (!canonical.length || (args.length == 1 && canonical != "-12345678901234567890.125"))
        return 2;
    return valid && decimal.unscaledValue().signum() == decimal.signum() && decimal.longValue() != 17
        && decimal.intValue() != 18 && decimal.floatValue() != 19 && decimal.doubleValue() != 20 ? 0 : 1;
}
