"""gs-rest-service: GET /greeting with a request counter, and Spring MVC's default error handling.

The cases run in order against one process, so the counter in `id` is part of the contract: every request that
reaches the handler (HEAD included) increments it, and requests that fail before the handler do not.
"""
from springsuite import Case

INSTANT = {'timestamp': 'instant'}
WHITELABEL = [(r"<div id='created'>[^<]*</div>", "<div id='created'>*</div>")]

CASES = [
    Case('default name', 'GET', '/greeting'),
    Case('name parameter', 'GET', '/greeting?name=User'),
    Case('percent-encoded UTF-8 name', 'GET', '/greeting?name=%C3%A9t%C3%A9'),
    Case('name with spaces and plus', 'GET', '/greeting?name=Jane+Q%20Public'),
    Case('empty name takes the default', 'GET', '/greeting?name='),
    Case('repeated name parameter joins with a comma', 'GET', '/greeting?name=a&name=b'),
    Case('JSON escaping', 'GET', '/greeting?name=%22quoted%22%5Cslash%3C%3E'),
    Case('unknown parameter is ignored', 'GET', '/greeting?other=1'),
    Case('Accept application/json', 'GET', '/greeting', headers={'Accept': 'application/json'}),
    Case('Accept application/xml is not acceptable', 'GET', '/greeting', headers={'Accept': 'application/xml'}),
    Case('HEAD reaches the handler', 'HEAD', '/greeting'),
    Case('OPTIONS lists the allowed methods', 'OPTIONS', '/greeting'),
    Case('POST is not allowed', 'POST', '/greeting', volatile=INSTANT),
    Case('DELETE is not allowed', 'DELETE', '/greeting', volatile=INSTANT),
    Case('unknown path is a JSON 404', 'GET', '/nope', volatile=INSTANT),
    Case('trailing slash does not match', 'GET', '/greeting/', volatile=INSTANT),
    Case('unknown path for a browser is the Whitelabel page', 'GET', '/nope',
         headers={'Accept': 'text/html'}, normalize=WHITELABEL),
    Case('counter after the errors', 'GET', '/greeting?name=again'),
]
