/++
`@Valid @RequestBody` through MockMvc: the argument is validated into a `BeanPropertyBindingResult` named after its
type, an invalid one raises `MethodArgumentNotValidException`, and advice reads its field errors, as
spring-petclinic-rest's `ExceptionControllerAdvice` does. The validator is spring-context's `Validator`
interface; Boot passes Hibernate Validator through `LocalValidatorFactoryBean`.
+/
module request_body_validation_tests;

import flint.engine.aot.any : Any;
import flint.http : HttpStatus, MediaType, ProblemDetail, ResponseEntity;
import flint.jakarta.validation : Valid;
import flint.test.web.servlet.request : MockMvcRequestBuilders;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import flint.test.web.servlet.setup : MockMvcBuilders;
import flint.validation : Errors, Validator;
import flint.web.bind : MethodArgumentNotValidException;
import flint.web.bind.annotation : ExceptionHandler, PostMapping, RequestBody, RestController, RestControllerAdvice;

@safe:

/// An owner as petclinic-rest posts it.
struct OwnerDto
{
    string firstName; ///
    string telephone; ///
}

/// Rejects a blank first name and a non-numeric telephone, as the DTO's constraints would.
private final class OwnerValidator : Validator
{
    bool supports(string typeName)
    {
        return typeName.length != 0;
    }

    void validate(Any target, Errors errors)
    {
        const owner = target.get!OwnerDto;
        if (owner.firstName.length == 0)
            errors.rejectValue("firstName", "NotBlank", "must not be blank");
        foreach (c; owner.telephone)
            if (c < '0' || c > '9')
            {
                errors.rejectValue("telephone", "Pattern", "must match \"^[0-9]*$\"");
                break;
            }
    }
}

/// `POST /owners`.
@RestController
class OwnerController
{
    int calls; /// handler invocations

    /// Echoes a valid owner.
    @PostMapping("/owners")
    OwnerDto addOwner(@Valid @RequestBody OwnerDto owner)
    {
        ++calls;
        return owner;
    }
}

/// Turns validation failures into a 400 ProblemDetail listing the field errors.
@RestControllerAdvice
class ValidationAdvice
{
    /// The advice's handler.
    @ExceptionHandler
    ResponseEntity handle(MethodArgumentNotValidException ex)
    {
        auto detail = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "Validation failed");
        string fields;
        foreach (error; ex.getBindingResult().getFieldErrors().toArray())
            fields ~= (fields.length ? "," : "") ~ ex.getObjectName() ~ "." ~ error.getField();
        detail.setTitle(fields);
        return ResponseEntity.badRequest().body(detail);
    }
}

@("@Valid @RequestBody: a valid body reaches the handler; an invalid one is MethodArgumentNotValidException")
unittest
{
    auto mockMvc = MockMvcBuilders.standaloneSetup(new OwnerController())
        .setControllerAdvice(new ValidationAdvice()).setValidator(new OwnerValidator()).build();
    mockMvc.perform(MockMvcRequestBuilders.post("/owners").contentType(MediaType.APPLICATION_JSON)
            .content(`{"firstName":"George","telephone":"6085551023"}`)).andExpect(MockMvcResultMatchers.status()
            .isOk()).andExpect(MockMvcResultMatchers.content()
            .string(`{"firstName":"George","telephone":"6085551023"}`));
    mockMvc.perform(MockMvcRequestBuilders.post("/owners").contentType(MediaType.APPLICATION_JSON)
            .content(`{"firstName":"","telephone":"01234abcde"}`)).andExpect(MockMvcResultMatchers.status()
            .isBadRequest()).andExpect(MockMvcResultMatchers.jsonPath("$.title")
            .value("ownerDto.firstName,ownerDto.telephone"));
}

@("Without a validator, @Valid arguments are not validated (Spring's NoOpValidator)")
unittest
{
    auto mockMvc = MockMvcBuilders.standaloneSetup(new OwnerController()).build();
    mockMvc.perform(MockMvcRequestBuilders.post("/owners").contentType(MediaType.APPLICATION_JSON)
            .content(`{"firstName":"","telephone":"x"}`)).andExpect(MockMvcResultMatchers.status().isOk());
}

/// Counts the interceptor callbacks, and what afterCompletion saw.
private final class CountingInterceptor : imported!"flint.web.servlet".HandlerInterceptor
{
    import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
    import flint.web.servlet : ModelAndView;

    int pre, post, after;
    Exception completedWith;

    override bool preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
    {
        ++pre;
        return true;
    }

    override void postHandle(HttpServletRequest request, HttpServletResponse response, Object handler,
            ModelAndView modelAndView)
    {
        ++post;
    }

    override void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex)
    {
        ++after;
        completedWith = ex;
    }
}

@("Flint: a validation failure reaches the advice as Spring's thrown exception would, without unwinding")
unittest
{
    // The stock adapter hands MethodArgumentNotValidException to doDispatch without a throw (DeferredFailure).
    // What Spring's throw would do is still observed: the handler never runs, postHandle is skipped,
    // afterCompletion sees the resolved request, and the advice answers.
    auto controller = new OwnerController();
    auto counting = new CountingInterceptor();
    auto mockMvc = MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(new ValidationAdvice())
        .setValidator(new OwnerValidator()).addInterceptors(counting).build();
    mockMvc.perform(MockMvcRequestBuilders.post("/owners").contentType(MediaType.APPLICATION_JSON)
            .content(`{"firstName":"","telephone":"x"}`)).andExpect(MockMvcResultMatchers.status().isBadRequest())
        .andExpect(MockMvcResultMatchers.jsonPath("$.title").value("ownerDto.firstName,ownerDto.telephone"));
    assert(controller.calls == 0);
    assert(counting.pre == 1 && counting.post == 0 && counting.after == 1 && counting.completedWith is null);
    mockMvc.perform(MockMvcRequestBuilders.post("/owners").contentType(MediaType.APPLICATION_JSON)
            .content(`{"firstName":"Ada","telephone":"1"}`)).andExpect(MockMvcResultMatchers.status().isOk());
    assert(controller.calls == 1);
    assert(counting.pre == 2 && counting.post == 1 && counting.after == 2);
}

@("Flint: a validation failure without advice is still Spring's 400 from DefaultHandlerExceptionResolver")
unittest
{
    auto controller = new OwnerController();
    auto mockMvc = MockMvcBuilders.standaloneSetup(controller).setValidator(new OwnerValidator()).build();
    mockMvc.perform(MockMvcRequestBuilders.post("/owners").contentType(MediaType.APPLICATION_JSON)
            .content(`{"firstName":"","telephone":"1"}`)).andExpect(MockMvcResultMatchers.status().isBadRequest());
    assert(controller.calls == 0);
}
