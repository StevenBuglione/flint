import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SPEC=importlib.util.spec_from_file_location('static_smoke',Path(__file__).resolve().parents[1]/'tools/static_smoke.py')
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)

def elf(segment_type=1,payload=b'',machine=62):
    ident=b'\x7fELF\x02\x01\x01'+bytes(9)
    header=struct.pack('<16sHHIQQQIHHHHHH',ident,2,machine,1,0x401000,64,0,0,64,56,1,0,0,0)
    segment=struct.pack('<IIQQQQQQ',segment_type,5,120,0x401000,0x401000,len(payload),len(payload),4096)
    return header+segment+payload

class StaticElfAuditTests(unittest.TestCase):
    def test_static_header_and_self_relocating_dynamic_table_allowed(self):
        self.assertFalse(m.inspect_elf(elf(),62)['has_interpreter'])
        x=m.inspect_elf(elf(2,struct.pack('<qQ',0,0)),62)
        self.assertEqual(x['needed_libraries'],[])

    def test_interpreter_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'PT_INTERP'):
            m.inspect_elf(elf(3,b'/lib/ld-musl-x86_64.so.1\0'),62)

    def test_needed_library_rejected_even_without_interpreter(self):
        dynamic=struct.pack('<qQqQ',1,7,0,0)
        with self.assertRaisesRegex(ValueError,'DT_NEEDED'):
            m.inspect_elf(elf(2,dynamic),62)

    def test_wrong_architecture_cannot_pass_cross_target_job(self):
        with self.assertRaisesRegex(ValueError,'architecture'):
            m.inspect_elf(elf(machine=62),183)

    def test_truncated_headers_and_overrunning_segment_rejected(self):
        with self.assertRaisesRegex(ValueError,'out of bounds'):
            m.inspect_elf(elf()[:100],62)
        damaged=bytearray(elf())
        struct.pack_into('<Q',damaged,64+8,2**64-16)
        struct.pack_into('<Q',damaged,64+32,128)
        with self.assertRaisesRegex(ValueError,'segment exceeds'):
            m.inspect_elf(damaged,62)

    def test_unterminated_dynamic_table_rejected(self):
        with self.assertRaisesRegex(ValueError,'DT_NULL'):
            m.inspect_elf(elf(2,struct.pack('<qQ',5,0x1234)),62)

    @unittest.skipUnless(sys.platform=='linux','requires the Linux ELF linker')
    def test_actual_dynamic_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            source=Path(temporary)/'dynamic.c';binary=Path(temporary)/'dynamic'
            source.write_text('#include <stdio.h>\nint main(void) { return puts("dynamic probe") < 0; }\n', encoding='utf-8', newline='\n')
            subprocess.run(['cc',str(source),'-Wl,-Bdynamic','-o',str(binary)],check=True,capture_output=True)
            data=binary.read_bytes();machine=struct.unpack_from('<H',data,18)[0]
            with self.assertRaisesRegex(ValueError,'PT_INTERP|DT_NEEDED'):
                m.inspect_elf(data,machine)

if __name__=='__main__':unittest.main()
