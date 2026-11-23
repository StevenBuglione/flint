/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.rest.validation`,
ported to Flint. Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- Java → D syntax, one module per Java package (R1); the constraint annotation is a struct (R2).
- Jakarta Validation finds `PetAgeValidator` through `@Constraint(validatedBy = ...)`; Flint binds validator
  classes explicitly (Hibernate Validator's `ConstraintMapping`), so `PetAgeValidationConfiguration` adds the binding
  as a `ValidationConfigurationCustomizer` bean.
+/
module org.springframework.samples.petclinic.rest.validation;

import flint.boot.validation.autoconfigure : ValidationConfigurationCustomizer;
import flint.context.annotation : Bean, Configuration;
import flint.hibernate.validator : HibernateValidatorConfiguration;
import flint.jakarta.validation : Constraint, ConstraintValidator, ConstraintValidatorContext;
import flint.java.lang : classOf;
import flint.java.time : LocalDate;
import JakartaValidation = flint.jakarta.validation;

@safe:

/// Validates that a pet's birth date is neither in the future nor more than 50 years ago.
@Constraint(validatedBy: [classOf!PetAgeValidator])
struct PetAgeValidation
{
    /// The default message.
    string message = "Birth date must not be in the future or older than 50 years";
}

/// The validator for `PetAgeValidation`.
class PetAgeValidator : ConstraintValidator!(PetAgeValidation, LocalDate)
{
    ///
    void initialize(PetAgeValidation)
    {
    }

    ///
    bool isValid(LocalDate birthDate, ConstraintValidatorContext context)
    {
        if (birthDate == LocalDate.init)
            return true;
        LocalDate today = LocalDate.now();
        if (birthDate.isAfter(today))
        {
            context.disableDefaultConstraintViolation();
            context.buildConstraintViolationWithTemplate("Birth date cannot be in the future").addConstraintViolation();
            return false;
        }
        if (birthDate.isBefore(today.minusYears(50)))
        {
            context.disableDefaultConstraintViolation();
            context.buildConstraintViolationWithTemplate("Birth date cannot be older than 50 years")
                .addConstraintViolation();
            return false;
        }
        return true;
    }
}

/// Binds `PetAgeValidator` to `PetAgeValidation` (see the module header).
@Configuration
class PetAgeValidationConfiguration
{
    /// The binding, applied to the application's validator configuration.
    @Bean
    ValidationConfigurationCustomizer petAgeValidation()
    {
        return new PetAgeValidationBinding();
    }
}

private final class PetAgeValidationBinding : ValidationConfigurationCustomizer
{
    void customize(JakartaValidation.Configuration configuration)
    {
        if (auto hibernate = cast(HibernateValidatorConfiguration) configuration)
        {
            auto mapping = hibernate.createConstraintMapping();
            mapping.constraintDefinition!PetAgeValidation().validatedBy!PetAgeValidator();
            hibernate.addMapping(mapping);
        }
    }
}
