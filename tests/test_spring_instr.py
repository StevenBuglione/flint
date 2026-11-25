"""tools/spring_instr.py: the benchmarked requests, the layer of a function, and the callgrind dump parser."""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import spring_instr  # noqa: E402


class RequestTests(unittest.TestCase):
    def test_the_four_benchmarked_requests_come_from_the_manifests(self):
        table = spring_instr.requests_by_name()
        self.assertEqual(set(table), {('gs-rest-service', 'greeting'), ('gs-rest-service', 'not-found'),
                                      ('petclinic-rest', 'owner'), ('petclinic-rest', 'validation-error')})
        invalid = spring_instr.find_request('petclinic-rest', 'invalid-post')
        self.assertEqual((invalid['method'], invalid['path'], invalid['status']), ('POST', '/petclinic/api/owners', 400))
        self.assertIn('telephone', invalid['body'])
        self.assertEqual(spring_instr.find_request('gs-rest-service', 'nope')['status'], 404)
        with self.assertRaises(SystemExit):
            spring_instr.find_request('gs-rest-service', 'owner')


class LayerTests(unittest.TestCase):
    def test_d_modules_and_c_symbols_go_to_their_layers(self):
        layer = spring_instr.layer_of
        self.assertEqual(layer('_D5flint6engine3web5http16Http1Reader7receiveMFZv', None), 'engine-web')
        self.assertEqual(layer('_D5flint6engine7reactor6Worker7executeMFZv', None), 'engine-reactor')
        self.assertEqual(layer('_D5flint3web7servlet17DispatcherServlet5serveMFZv', None), 'webmvc')
        self.assertEqual(layer('_D4core8internal2gc4impl12conservativeQw3Gcx4markMFZv', None), 'druntime-gc')
        self.assertEqual(layer('_D4core8internal5array8equalityQjFZb', None), 'druntime')
        self.assertEqual(layer('_D3org15springframework7samples9petclinic5model5OwnerQgFZv', None), 'app')
        self.assertEqual(layer('PQexecParams', '/x/petclinic-rest-flint'), 'libpq')
        self.assertEqual(layer('__memcpy_avx_unaligned_erms', '/usr/lib/x86_64-linux-gnu/libc.so.6'), 'libc')
        self.assertEqual(layer('relay', '/x/gs-rest-service-flint'), 'llhttp')
        self.assertEqual(layer('mystery', '/x/app'), 'other')


DUMP = """version: 1
creator: callgrind-3.22.0
events: Ir
summary: 1000

ob=/x/app
fl=/src/a.d
fn=_D5flint6engine7reactor6Worker7executeMFZv
10 300
cob=/x/app
cfi=/src/b.d
cfn=_D5flint3web7servlet17DispatcherServlet5serveMFZv
calls=2 20
11 650
12 50
fn=_D5flint3web7servlet17DispatcherServlet5serveMFZv
20 400
cfn=_D4core8internal2gc4impl12conservativeQw14ConservativeGC6mallocMFNbmkxC8TypeInfoZPv
calls=3 30
21 250
fn=_D4core8internal2gc4impl12conservativeQw14ConservativeGC6mallocMFNbmkxC8TypeInfoZPv
30 250
totals: 1000
"""


class ParserTests(unittest.TestCase):
    def test_own_costs_skip_inclusive_call_lines_and_gc_calls_are_counted(self):
        with tempfile.TemporaryDirectory() as directory:
            dump = Path(directory) / 'callgrind.out.1'
            dump.write_text(DUMP)
            result = spring_instr.parse_callgrind(dump)
        self.assertEqual(result['total'], 1000)
        self.assertEqual(result['layers'], {'engine-reactor': 350, 'webmvc': 400, 'druntime-gc': 250})
        self.assertEqual(result['own_sum'], result['total'], 'the layers add up to the total')
        self.assertEqual(result['gc_calls'], 3)


if __name__ == '__main__':
    unittest.main()
