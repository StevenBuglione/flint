module aspectj_instantiation_contract_tests;

import flint.aop : PointcutAdvisor;
import flint.aop.aspectj : AspectInstanceFactory, InstantiationModelAwarePointcutAdvisor;
import flint.core : Ordered;
import flint.engine.aot.any : Any;

@safe:

static assert(is(AspectInstanceFactory == interface));
static assert(is(AspectInstanceFactory : Ordered));
static assert(is(typeof(AspectInstanceFactory.init.getAspectInstance()) == Any));

static assert(is(InstantiationModelAwarePointcutAdvisor == interface));
static assert(is(InstantiationModelAwarePointcutAdvisor : PointcutAdvisor));
static assert(is(typeof(InstantiationModelAwarePointcutAdvisor.init.isLazy()) == bool));
static assert(is(typeof(InstantiationModelAwarePointcutAdvisor.init.isAdviceInstantiated()) == bool));
