import copy
import importlib.util
from pathlib import Path
import unittest

SPEC=importlib.util.spec_from_file_location(
    "load_bench",Path(__file__).resolve().parents[1]/"tools/load_bench.py")
m=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)

class OhaEvidenceTests(unittest.TestCase):
    def payload(self):
        return {
            "summary":{"successRate":1,"total":60,"requestsPerSec":20000,
                       "totalData":1200000*26,"sizePerRequest":26},
            "statusCodeDistribution":{"200":1200000},"errorDistribution":{},
            "latencyPercentiles":{"p50":.001,"p99":.003,"p99.9":.009}
        }

    def test_seconds_to_milliseconds_and_exact_count(self):
        x=m.parse_oha(self.payload(),200,26)
        self.assertEqual((x["p50_ms"],x["p99_ms"],x["p999_ms"]),(1,3,9))
        self.assertEqual(x["count"],1200000)

    def test_transport_errors_fail_even_when_success_rate_claims_one(self):
        x=self.payload();x["errorDistribution"]={"deadline":1}
        with self.assertRaisesRegex(ValueError,"transport"):
            m.parse_oha(x,200,26)

    def test_wrong_status_and_body_size_fail(self):
        x=self.payload();x["statusCodeDistribution"]={"200":1199999,"500":1}
        with self.assertRaises(ValueError):m.parse_oha(x,200,26)
        x=self.payload();x["summary"]["totalData"]-=1
        with self.assertRaises(ValueError):m.parse_oha(x,200,26)

    def test_missing_tail_and_nonfinite_data_fail(self):
        x=self.payload();del x["latencyPercentiles"]["p99.9"]
        with self.assertRaises(KeyError):m.parse_oha(x,200,26)
        x=self.payload();x["latencyPercentiles"]["p99.9"]=float("nan")
        with self.assertRaises(ValueError):m.parse_oha(x,200,26)

    def test_zero_count_and_reversed_percentiles_fail(self):
        x=self.payload();x["statusCodeDistribution"]["200"]=0
        with self.assertRaises(ValueError):m.parse_oha(x,200,26)
        x=self.payload();x["latencyPercentiles"]["p99.9"]=.0001
        with self.assertRaises(ValueError):m.parse_oha(x,200,26)

    def test_cpu_range_parser(self):
        self.assertEqual(m.cpu_list("0-2,4,8-9"),{0,1,2,4,8,9})

if __name__=="__main__":
    unittest.main()
