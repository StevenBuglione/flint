module flint.bean_definition_defaults_test;

import flint.beans.factory.support : BeanDefinitionDefaults;
import std.typecons : Nullable;

@safe:

@("bean definition defaults distinguish an unset lazy flag from explicit false")
unittest
{
    auto defaults = new BeanDefinitionDefaults;
    assert(defaults.getLazyInit().isNull && !defaults.isLazyInit());
    assert(defaults.getAutowireMode() == 0 && defaults.getDependencyCheck() == 0);
    assert(defaults.getInitMethodName().isNull && defaults.getDestroyMethodName().isNull);

    defaults.setLazyInit(false);
    auto lazyFlag = defaults.getLazyInit();
    assert(!lazyFlag.isNull && !lazyFlag.get() && !defaults.isLazyInit());
    defaults.setLazyInit(true);
    lazyFlag = defaults.getLazyInit();
    assert(!lazyFlag.isNull && lazyFlag.get() && defaults.isLazyInit());

    defaults.setAutowireMode(2);
    defaults.setDependencyCheck(3);
    assert(defaults.getAutowireMode() == 2 && defaults.getDependencyCheck() == 3);
}

@("bean callback defaults retain nonblank names and clear blank or null names")
unittest
{
    auto defaults = new BeanDefinitionDefaults;
    defaults.setInitMethodName(Nullable!string(" initialize "));
    defaults.setDestroyMethodName(Nullable!string("shutdown"));
    assert(defaults.getInitMethodName().get() == " initialize ");
    assert(defaults.getDestroyMethodName().get() == "shutdown");

    defaults.setInitMethodName(Nullable!string("\t\u2003 "));
    defaults.setDestroyMethodName(Nullable!string.init);
    assert(defaults.getInitMethodName().isNull && defaults.getDestroyMethodName().isNull);
}
