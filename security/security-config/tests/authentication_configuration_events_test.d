// Ported from spring-security 7.2.0: config/src/test/java/org/springframework/security/config/annotation/authentication/configuration/AuthenticationConfigurationPublishTests.java
/*
 * Copyright 2004-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the Flint authors.
 */
module flint.security.authentication_configuration_events_test;

import flint.context : ApplicationListener;
import flint.context.support : GenericApplicationContext;
import flint.engine.aot.any : Any;
import flint.security.authentication : AuthenticationEventPublisher, AuthenticationProvider,
    DefaultAuthenticationEventPublisher, UsernamePasswordAuthenticationToken;
import flint.security.authentication.event : AuthenticationSuccessEvent;
import flint.security.config.annotation.authentication.configuration : AuthenticationConfiguration;
import flint.security.core : Authentication, AuthenticationException, AuthorityUtils;
import flint.security.core.userdetails : User, UserDetailsService;
import flint.security.crypto.password : NoOpPasswordEncoder, PasswordEncoder;
import flint.security.provisioning : InMemoryUserDetailsManager;

@safe:

private final class RecordingListener : ApplicationListener!AuthenticationSuccessEvent
{
    AuthenticationSuccessEvent event;
    size_t events;

    override void onApplicationEvent(AuthenticationSuccessEvent event)
    {
        this.event = event;
        ++events;
    }
}

private User testUser()
{
    return new User("user", "password", AuthorityUtils.createAuthorityList("ROLE_USER"));
}

private Authentication request()
{
    return UsernamePasswordAuthenticationToken.unauthenticated(Any.of("user"), Any.of("password"));
}

private GenericApplicationContext userContext()
{
    auto context = new GenericApplicationContext;
    context.registerBean!PasswordEncoder("encoder", () => NoOpPasswordEncoder.getInstance());
    context.registerBean!UserDetailsService("users", () => new InMemoryUserDetailsManager(testUser()));
    return context;
}

@("authenticationEventPublisherBeanUsedByDefault")
unittest
{
    auto context = userContext();
    context.registerBean!DefaultAuthenticationEventPublisher("events");
    auto listener = new RecordingListener;
    context.addApplicationListener(listener);
    scope (exit)
        context.close();
    context.refresh();

    auto configuration = new AuthenticationConfiguration(context);
    auto result = configuration.getAuthenticationManager().authenticate(request());
    assert(listener.events == 1 && listener.event.getAuthentication() is result);
    assert(result.getCredentials().isNull);
}

@("AuthenticationConfiguration publishes through the context without a publisher bean")
unittest
{
    auto context = userContext();
    auto listener = new RecordingListener;
    context.addApplicationListener(listener);
    scope (exit)
        context.close();
    context.refresh();

    auto configuration = new AuthenticationConfiguration(context);
    configuration.authenticationManagerBuilder().userDetailsService(context.getBean!UserDetailsService());
    auto result = configuration.getAuthenticationManager().authenticate(request());
    assert(listener.events == 1 && listener.event.getAuthentication() is result);
}

private final class AcceptingProvider : AuthenticationProvider
{
    Authentication authenticate(Authentication authentication)
    {
        return UsernamePasswordAuthenticationToken.authenticated(authentication.getPrincipal(),
                authentication.getCredentials(), AuthorityUtils.createAuthorityList("ROLE_USER"));
    }

    bool supports(string authenticationType)
    {
        return true;
    }
}

private final class RecordingPublisher : AuthenticationEventPublisher
{
    Authentication result;
    size_t events;

    void publishAuthenticationFailure(AuthenticationException exception, Authentication authentication)
    {
        assert(false, "Unexpected authentication failure");
    }

    void publishAuthenticationSuccess(Authentication authentication)
    {
        result = authentication;
        ++events;
    }
}

@("AuthenticationConfiguration uses the primary publisher for an AuthenticationProvider bean")
unittest
{
    auto context = new GenericApplicationContext;
    auto primary = new RecordingPublisher;
    auto secondary = new RecordingPublisher;
    context.registerBean!AuthenticationProvider("provider", () => new AcceptingProvider);
    context.registerBean!AuthenticationEventPublisher("secondary", () => secondary);
    context.registerBean!AuthenticationEventPublisher("primary", () => primary,
            definition => definition.setPrimary(true));
    scope (exit)
        context.close();
    context.refresh();

    auto configuration = new AuthenticationConfiguration(context);
    auto result = configuration.getAuthenticationManager().authenticate(request());
    assert(primary.events == 1 && primary.result is result);
    assert(secondary.events == 0);
}
