/*
 * Copyright 2023-present the original author or authors.
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
 */

module evaluation_request_contract_tests;

import flint.ai.document : Document;
import flint.ai.evaluation : EvaluationRequest, EvaluationResponse, Evaluator;
import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException, UnsupportedOperationException;
import flint.java.util : ArrayList, HashMap, List;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private Document document(string text)
{
    return new Document("fixture", Nullable!string(text), new HashMap!(string, Any)());
}

@("evaluation request overloads retain Java defaults and typed nulls")
unittest
{
    auto request = new EvaluationRequest("query", "response");
    auto peer = new EvaluationRequest("query", "response");
    assert(request.getUserText() == "query" && request.getResponseContent() == "response");
    assert(request.getDataList().isEmpty() && request.getDataList() is peer.getDataList());
    assert(collectException!UnsupportedOperationException(request.getDataList().add(document("text"))) !is null);

    auto noText = new EvaluationRequest(cast(string) null, "response");
    auto noData = new EvaluationRequest(cast(List!Document) null, "response");
    assert(noText.getUserText() is null && noText.getDataList().isEmpty());
    assert(noData.getUserText() !is null && noData.getUserText().length == 0 && noData.getDataList() is null);
    assert(noText != new EvaluationRequest("", "response"));
    static assert(!__traits(compiles, new EvaluationRequest(null, "response")));
}

@("evaluation request equality and Java hash use the live document list")
unittest
{
    auto documents = new ArrayList!Document();
    auto peers = new ArrayList!Document();
    auto request = new EvaluationRequest("query", documents, "response");
    auto peer = new EvaluationRequest("query", peers, "response");
    assert(request.getDataList() is documents);
    assert(request == peer && request.hashCode() == peer.hashCode());
    // Java 21 Objects.hash("q", Collections.emptyList(), "a").
    assert((new EvaluationRequest("q", "a")).hashCode() == 138_512);
    documents.add(document("text"));
    assert(request != peer);
    peers.add(document("text"));
    assert(request == peer && request.hashCode() == peer.hashCode());
}

@("evaluation request displays Java labels and null fields")
unittest
{
    const expected = "EvaluationRequest{userText='null', dataList=null, chatResponse=null}";
    assert((new EvaluationRequest(null, null, null)).toString() == expected);
    auto documents = new ArrayList!Document();
    auto request = new EvaluationRequest(documents, "answer");
    assert(request.toString() == "EvaluationRequest{userText='', dataList=[], chatResponse=answer}");
}

private final class LocalEvaluator : Evaluator
{
    mixin Evaluator.Defaults!();

    override EvaluationResponse evaluate(EvaluationRequest request)
    {
        return new EvaluationResponse(true, doGetSupportingData(request), null);
    }
}

@("evaluator joins nonblank document text in list order")
unittest
{
    auto documents = new ArrayList!Document();
    documents.add(document("  first  "));
    documents.add(document("\t\u2003\n"));
    documents.add(document(""));
    documents.add(document("\u00a0"));
    documents.add(document("last"));
    version (Windows)
        enum separator = "\r\n";
    else
        enum separator = "\n";
    enum expected = "  first  " ~ separator ~ "\u00a0" ~ separator ~ "last";
    Evaluator evaluator = new LocalEvaluator();
    auto request = new EvaluationRequest(documents, "answer");
    assert(evaluator.doGetSupportingData(request) == expected);
    assert(evaluator.evaluate(request).getFeedback() == expected);
    const empty = evaluator.doGetSupportingData(new EvaluationRequest("query", "answer"));
    assert(empty !is null && empty.length == 0);
}

@("evaluator rejects null Java dereferences")
unittest
{
    Evaluator evaluator = new LocalEvaluator();
    auto noData = new EvaluationRequest(cast(List!Document) null, "answer");
    auto documents = new ArrayList!Document();
    documents.add(null);
    assert(collectException!NullPointerException(evaluator.doGetSupportingData(null)) !is null);
    assert(collectException!NullPointerException(evaluator.doGetSupportingData(noData)) !is null);
    assert(collectException!NullPointerException(evaluator.doGetSupportingData(new EvaluationRequest(documents,
            "answer"))) !is null);
}
