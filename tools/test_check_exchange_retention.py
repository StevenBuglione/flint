"""Unit tests of the exchange pool's retention audit: `python3 tools/test_check_exchange_retention.py`."""
import tempfile
import unittest
from pathlib import Path

import check_exchange_retention as audit


def holders(source):
    return [(owner, field) for owner, field, _ in audit.holders('x.d', source)]


class Holders(unittest.TestCase):
    def test_a_singleton_field_is_found(self):
        source = '''
@safe:
/// Keeps the HttpServletRequest of the last call: { not code }
@Component
final class LastRequest
{
    private HttpServletRequest last;
    HttpServletResponse[] responses;
    void remember(HttpServletRequest request) { last = request; }
}
'''
        self.assertEqual(holders(source), [('LastRequest', 'last'), ('LastRequest', 'responses')])

    def test_module_and_static_variables_are_found(self):
        source = '''
__gshared ServletRequest shared_;
private ServletEngineResponse lastResponse = null;
struct Cache { static HttpServletRequest current; }
'''
        self.assertEqual(holders(source), [(None, 'shared_'), (None, 'lastResponse'), ('Cache', 'current')])

    def test_parameters_locals_and_methods_are_not_fields(self):
        source = '''
interface Resolver
{
    HttpServletRequest getRequest();
    void resolve(HttpServletRequest request, HttpServletResponse response);
}
void handle(HttpServletRequest request)
{
    HttpServletRequest wrapped = request;
    foreach (r; [request]) { ServletRequest inner = r; }
    auto lambda = (HttpServletRequest r) { HttpServletResponse local; };
}
'''
        self.assertEqual(holders(source), [])

    def test_version_blocks_and_nested_classes_keep_their_scope(self):
        source = '''
class Outer
{
    version (linux)
    {
        private const(HttpServletRequest) kept;
    }
    static final class Inner { ServletOutputStream stream; }
    void method() { class Local { HttpServletResponse held; } }
}
'''
        self.assertEqual(holders(source), [('Outer', 'kept'), ('Inner', 'stream'), ('Local', 'held')])

    def test_comments_and_strings_hide_declarations(self):
        source = '''
/+ class Fake { HttpServletRequest gone; } +/
enum text = "class Q { HttpServletRequest notHere; }";
// HttpServletRequest commented;
class Real { char brace = '{'; HttpServletRequest kept; }
'''
        self.assertEqual(holders(source), [('Real', 'kept')])


class Violations(unittest.TestCase):
    def test_an_unreviewed_holder_fails_and_test_sources_are_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'framework/demo/source/flint/demo.d'
            source.parent.mkdir(parents=True)
            source.write_text('class Keeper { HttpServletRequest kept; }\n')
            tests = root / 'framework/demo/tests/demo_tests.d'
            tests.parent.mkdir(parents=True)
            tests.write_text('class Stash { HttpServletRequest stash; }\n')
            self.assertEqual(audit.violations(root),
                             ['framework/demo/source/flint/demo.d:1: Keeper.kept holds a servlet exchange object'])

    def test_the_tree_has_only_reviewed_holders(self):
        self.assertEqual(audit.violations(), [])

    def test_every_allowlist_entry_still_exists(self):
        found = set()
        for relative, _, _ in audit.ALLOWED:
            path = audit.ROOT / relative
            for owner, field, _ in audit.holders(relative, path.read_text(encoding='utf-8')):
                found.add((relative, owner, field))
        self.assertEqual(set(audit.ALLOWED) - found, set(), 'a stale allowlist entry')


if __name__ == '__main__':
    unittest.main()
