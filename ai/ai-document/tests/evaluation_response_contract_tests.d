module evaluation_response_contract_tests;

import flint.ai.evaluation : EvaluationResponse;
import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashMap, Map;

@safe:

private alias Metadata = Map!(string, Any);

private final class ExtendedResponse : EvaluationResponse
{
    this(Metadata metadata)
    {
        super(true, 0.5f, "looks good", metadata);
    }
}

@("evaluation response retains the supplied map and defaults its score to positive zero")
unittest
{
    auto metadata = new LinkedHashMap!(string, Any)();
    auto response = new EvaluationResponse(true, "looks good", metadata);
    assert(response.isPass());
    assert(response.getScore() == 0.0f && 1.0f / response.getScore() == float.infinity);
    assert(response.getFeedback() == "looks good" && response.getMetadata() is metadata);
    metadata.put("source", Any.of("fixture"));
    assert(response.getMetadata().get("source").get!string == "fixture");
}

@("evaluation response compares by value including subclasses and Java float edge cases")
unittest
{
    auto first = new EvaluationResponse(true, 0.5f, "looks good", Metadata.of("source", Any.of("fixture")));
    auto second = new ExtendedResponse(Metadata.of("source", Any.of("fixture")));
    assert(first !is second && first.equals(second) && second.equals(first));
    assert(first == second && first.hashCode() == second.hashCode());
    assert(!first.equals(null) && !first.equals(new Object()));
    assert(!first.equals(new EvaluationResponse(false, 0.5f, "looks good", first.getMetadata())));
    assert(!first.equals(new EvaluationResponse(true, 0.5f, "another", first.getMetadata())));
    assert(!first.equals(new EvaluationResponse(true, 0.5f, "looks good", Metadata.of())));

    auto positiveZero = new EvaluationResponse(false, 0.0f, "", null);
    auto negativeZero = new EvaluationResponse(false, -0.0f, "", null);
    assert(positiveZero != negativeZero && positiveZero.hashCode() != negativeZero.hashCode());
    assert(positiveZero != new EvaluationResponse(false, 0.0f, null, null));

    auto firstNaN = new EvaluationResponse(false, float.nan, "", null);
    auto secondNaN = new EvaluationResponse(false, -float.nan, "", null);
    assert(firstNaN == secondNaN && firstNaN.hashCode() == secondNaN.hashCode());
}

@("evaluation response uses Java scalar hashing and display")
unittest
{
    auto response = new EvaluationResponse(true, 0.5f, "é", null);
    assert(response.hashCode() == -2_126_657_399);
    assert(response.toHash() == cast(uint) response.hashCode());
    assert(response.toString() == "EvaluationResponse{pass=true, score=0.5, feedback='é', metadata=null}");

    auto another = new EvaluationResponse(false, -0.0f, null, Metadata.of("label", Any.of("yes")));
    assert(another.toString() == "EvaluationResponse{pass=false, score=-0.0, feedback='null', metadata={label=yes}}");
}
