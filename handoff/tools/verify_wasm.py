#!/usr/bin/env python3
import argparse,json,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--ldc',default='ldc2');ap.add_argument('--node',default='node');a=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix='flint-abi-') as t:
        out=Path(t)/'probe.wasm'
        command=[a.ldc,'-betterC','-mtriple=wasm32-unknown-unknown-wasm','-Oz','-link-internally','-L--no-entry','-L--export=probe_build','-L--export=probe_pointer','-L--export-memory','-of='+str(out),str(ROOT/'verification/probes/wasm_abi.d')]
        subprocess.run(command,check=True);subprocess.run([a.node,str(ROOT/'verification/probes/wasm_abi_test.mjs'),str(out)],check=True)
        print(json.dumps({'wasm_bytes':out.stat().st_size,'link_and_execute':'passed'}))
if __name__=='__main__':main()
