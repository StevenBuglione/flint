module advisor_chain_contract_tests;

import flint.aop.framework : Advised, AdvisorChainFactory, AopInfrastructureBean;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, MemberDescriptorRef;
import flint.java.util : List;

@safe:

static assert(is(AdvisorChainFactory == interface));
static assert(is(typeof(AdvisorChainFactory.init.getInterceptorsAndDynamicInterceptionAdvice(Advised.init,
        MemberDescriptorRef.init, Descriptor.init)) == List!Any));
static assert(is(AopInfrastructureBean == interface));
