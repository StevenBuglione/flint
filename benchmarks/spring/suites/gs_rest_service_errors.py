"""gs-rest-service's error responses, for the default-JSON-404 specialization (Astra error-paths action 3).

Not a benchmark suite: tools/spring_error_identity.py runs these requests against the Java reference to record
golden/gs-rest-service-errors.json, then against two Flint builds, the specialization on and off. Both must match the
golden exactly, and each other byte for byte once the clock is masked.

A request is raw: the bytes of its request line and header fields are sent as written, so a case can repeat a field,
leave `Accept` out or put bytes in the path that an HTTP library would encode. Each run is one process with the
arguments it names; within a run the cases go in order, each on its own connection, followed by a probe request on
the same socket that records whether the server kept it.

Cases in which the specialization writes: a 404 for any method but HEAD, with no `Accept`, `*/*` or
`application/json`. Cases in which it must decline, so the generic error dispatch writes: HEAD, HTML, a q-value,
two `Accept` fields, a path too long for its stack copy, and every run whose error properties depend on the request.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Request:
    name: str
    method: str
    target: str
    fields: list = field(default_factory=list)  # [(name, value)], in order; `Host` is added first
    body: bytes = b''


@dataclass
class Run:
    label: str
    properties: dict  # Boot 4's `spring.web.error.*` keys without `spring.`; Flint's take `flint.` (ADR-030)
    requests: list

    def args(self, implementation):
        prefix = 'spring.' if implementation.startswith('java') else 'flint.'
        return [f'--{prefix}{key}={value}' for key, value in self.properties.items()]


JSON = [('Content-Type', 'application/json')]
LONG = '/' + 'x' * 3000

DEFAULT = [
    Request('no Accept', 'GET', '/nope'),
    Request('Accept */*', 'GET', '/nope', [('Accept', '*/*')]),
    Request('Accept application/json', 'GET', '/nope', [('Accept', 'application/json')]),
    Request('nested path', 'GET', '/a/b/c', [('Accept', '*/*')]),
    Request('trailing slash after a mapped path', 'GET', '/greeting/', [('Accept', '*/*')]),
    Request('percent-encoded quotes', 'GET', '/nope%22q%22', [('Accept', '*/*')]),
    Request('percent-encoded quote and backslash', 'GET', '/nope%22q%22%5Cs', [('Accept', '*/*')]),
    Request('percent-encoded UTF-8', 'GET', '/caf%C3%A9', [('Accept', '*/*')]),
    Request('percent-encoded control characters', 'GET', '/c%01t%1Fl%7F', [('Accept', '*/*')]),
    Request('raw UTF-8 in the path', 'GET', '/café', [('Accept', '*/*')]),
    Request('query string', 'GET', '/nope?x=1&y=%22z%22&path=false', [('Accept', '*/*')]),
    Request('empty query string', 'GET', '/nope?', [('Accept', '*/*')]),
    Request('POST with a body', 'POST', '/nope', [('Accept', '*/*')] + JSON, b'{"a":1}'),
    Request('PUT with a body', 'PUT', '/nope', [('Accept', '*/*')] + JSON, b'{}'),
    Request('PATCH without a body', 'PATCH', '/nope', [('Accept', '*/*'), ('Content-Length', '0')]),
    Request('DELETE', 'DELETE', '/nope', [('Accept', '*/*')]),
    Request('OPTIONS', 'OPTIONS', '/nope', [('Accept', '*/*')]),
    # The specialization declines these; the generic dispatch answers.
    Request('HEAD', 'HEAD', '/nope', [('Accept', '*/*')]),
    Request('Accept text/html', 'GET', '/nope', [('Accept', 'text/html')]),
    Request('Accept with a q-value', 'GET', '/nope', [('Accept', 'application/json;q=0.9')]),
    Request('Accept with two types', 'GET', '/nope', [('Accept', 'application/json, text/plain')]),
    Request('two Accept fields', 'GET', '/nope', [('Accept', 'application/json'), ('Accept', '*/*')]),
    Request('Accept application/xml', 'GET', '/nope', [('Accept', 'application/xml')]),
    Request('path longer than the stack copy', 'GET', LONG, [('Accept', '*/*')]),
    # The specialization is per request: a mapped request between errors is unaffected.
    Request('mapped request after the errors', 'GET', '/greeting?name=after', [('Accept', '*/*')]),
]

ON_PARAM = [
    Request('path parameter absent', 'GET', '/nope', [('Accept', '*/*')]),
    Request('path=false', 'GET', '/nope?path=false', [('Accept', '*/*')]),
    Request('path=true', 'GET', '/nope?path=true', [('Accept', '*/*')]),
]

RUNS = [
    Run('default', {}, DEFAULT),
    # Request-dependent error properties: no specialization is installed, and the generic path must still answer.
    Run('include-message always', {'web.error.include-message': 'always'},
        [Request('no Accept', 'GET', '/nope'), Request('Accept */*', 'GET', '/nope', [('Accept', '*/*')])]),
    Run('include-path on-param', {'web.error.include-path': 'on-param'}, ON_PARAM),
    Run('include-path never', {'web.error.include-path': 'never'},
        [Request('Accept */*', 'GET', '/nope', [('Accept', '*/*')])]),
]

# Differences from the Java reference that the specialization does not cause: both builds show them, on and off.
# check reports them apart and fails only on anything else, or once one of them stops differing (then remove it).
KNOWN = {
    ('default', 'percent-encoded quote and backslash'):
        "Tomcat rejects an encoded backslash (%5C) in the path with its HTML 400 and closes; Flint answers the 404",
    ('default', 'raw UTF-8 in the path'):
        "Tomcat rejects a raw non-ASCII byte in the request line with its HTML 400; Flint's 400 is engine-web's JSON",
    ('default', 'HEAD'):
        "Tomcat sends no Transfer-Encoding on a HEAD response without a length; Flint sends 'chunked'",
    ('include-path on-param', 'path=true'):
        "include-path=on-param with ?path=true includes the path in Boot; Flint's DefaultErrorAttributes leaves it out",
}
