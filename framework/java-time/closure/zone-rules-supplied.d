module app;

import flint.java.time.zone.zonerules : ZoneRules;
import std.traits : Parameters;

@safe:

int main(string[] args)
{
    alias Offset = Parameters!(ZoneRules.of)[0];
    alias DateTime = Parameters!(ZoneRules.isValidOffset)[0];
    alias History = typeof(ZoneRules.init.getTransitions());
    alias Annual = typeof(ZoneRules.init.getTransitionRules());
    alias Transition = typeof(History.init.get(0));
    alias Rule = typeof(Annual.init.get(0));
    alias Month = typeof(Rule.init.getMonth());
    const year = 1970 + cast(int)(args.length % 100);
    const winter = Offset.ofTotalSeconds(3_600);
    const summer = Offset.ofTotalSeconds(7_200);
    const spring = Transition.of(DateTime.of(year, 3, 1, 2, 0), winter, summer);
    const autumn = Transition.of(DateTime.of(year, 10, 1, 3, 0), summer, winter);
    const march = Rule.of(Month.MARCH, 1, Rule.init.getDayOfWeek(), Rule.init.getLocalTime(),
            false, Rule.TimeDefinition.WALL, winter, winter, summer);
    const october = Rule.of(Month.OCTOBER, 1, Rule.init.getDayOfWeek(), Rule.init.getLocalTime(),
            false, Rule.TimeDefinition.WALL, winter, summer, winter);
    const rules = ZoneRules.of(winter, winter, History.of(), History.of(spring, autumn), Annual.of(march, october));
    const query = DateTime.of(year + 1, 3, 1, 1, 0).toInstant(winter);
    const next = rules.nextTransition(query);
    const epoch = next.isNull ? 0 : next.get().toEpochSecond();
    return cast(int)(rules.getOffset(query).getTotalSeconds() + epoch + rules.hashCode()) & 127;
}
