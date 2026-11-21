#!/usr/bin/env python3
"""Compile TUI/WASM API contracts, concrete usage, and borrowing rejections."""
import argparse,datetime,hashlib,json,pathlib,re,subprocess,tempfile

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--dmd',default='dmd');parser.add_argument('--ldc',default='ldc2');parser.add_argument('--out',default='verification/tui-wasm-contracts.json');a=parser.parse_args()
    root=pathlib.Path(__file__).resolve().parents[1]
    mods=['cli','term','style','tui','widgets','prompt','os','wasm_bridge','ui_signals','wasi']
    modules=['contracts/source/flint/'+x+'.d' for x in mods]
    fixtures=root/'verification/tui-wasm/fixtures';fixtures.mkdir(parents=True,exist_ok=True)
    for name in ['cli','style','tui','wasm-bridge','ui-signals','wasi']:
        text=next((root/'specs').glob('tier-*/'+name+'.md')).read_text();blocks=re.findall(r'```d\n(.*?)\n```',text,re.S)
        (fixtures/(name.replace('-','_')+'_usage.d')).write_text('module '+name.replace('-','_')+'_usage;\n'+blocks[-1]+'\n')
    positive=fixtures/'wasm_lifetime_usage.d'
    positive.write_text('''module wasm_lifetime_usage;
import core.lifetime : move;
import flint.wasm_bridge : CommandBuffer, NodeHandle;
import flint.ui_signals : SignalGraph, SignalSlot, ObserverSlot;
void usage() @safe nothrow @nogc {
    ubyte[256] memory;
    auto created = CommandBuffer.fromStorage(memory[]);
    scope CommandBuffer buffer = move(created.value);
    SignalSlot[8] signals;
    ObserverSlot[8] observers;
    uint[8] queue;
    auto result = SignalGraph.fromStorage(signals[], observers[], queue[]);
    scope SignalGraph graph = move(result.value);
    auto id = graph.create(4);
    auto error = graph.bindText(id.value, NodeHandle(0, 1));
    error = graph.set(id.value, 5);
    error = graph.flush(buffer);
    error = buffer.visit((scope const(ubyte)[] bytes) @safe nothrow @nogc { assert(bytes.length >= 32); });
}
''')
    (fixtures/'cli_main_usage.d').write_text('''module cli_main_usage;
import flint.cli : Command, Option, parse;
@Command("hello", "A real main signature")
struct Options { @Option("name", 'n', "Name") string name = "world"; }
int main(string[] args) @safe {
    auto parsed = parse!Options(args[1 .. $]);
    return parsed.options.name.length == 0 ? 1 : 0;
}
''')
    negatives={
      'buffer_escape.d':'''module buffer_escape;
import core.lifetime : move;
import flint.wasm_bridge : CommandBuffer;
CommandBuffer leak() @safe nothrow @nogc {
    ubyte[64] localMemory;
    auto result = CommandBuffer.fromStorage(localMemory[]);
    return move(result.value);
}
''',
      'graph_escape.d':'''module graph_escape;
import core.lifetime : move;
import flint.ui_signals : SignalGraph, SignalSlot, ObserverSlot;
SignalGraph leak() @safe nothrow @nogc {
    SignalSlot[4] signals;
    ObserverSlot[4] observers;
    uint[4] queue;
    auto result = SignalGraph.fromStorage(signals[], observers[], queue[]);
    return move(result.value);
}
''',
      'callback_escape.d':'''module callback_escape;
import flint.wasm_bridge : CommandBuffer;
const(ubyte)[] retained;
void leak(ref scope CommandBuffer buffer) @safe nothrow @nogc {
    auto error = buffer.visit((scope const(ubyte)[] bytes) @safe nothrow @nogc { retained = bytes; });
}
'''
    }
    for name,text in negatives.items():(fixtures/name).write_text(text)
    checks=[]
    def run(label,cmd,reject=False):
        r=subprocess.run([str(x) for x in cmd],cwd=root,text=True,capture_output=True)
        passed=(r.returncode!=0 and ('scope' in r.stderr.lower() or 'stack' in r.stderr.lower())) if reject else r.returncode==0
        checks.append({'name':label,'command':[str(x) for x in cmd],'expected':'borrowing rejection' if reject else 'compile success','exit_code':r.returncode,'passed':passed,'stdout':r.stdout,'stderr':r.stderr})
        print(label,'PASS' if passed else 'FAIL')
        if not passed:print(r.stderr)
    for compiler in [a.dmd,a.ldc]:
        name=pathlib.Path(compiler).name;base=[compiler,'-c','-o-','-preview=dip1000','-Icontracts/source']
        run(name+'-native-contracts',base+modules)
        for fixture in sorted(fixtures.glob('*_usage.d')):run(name+'-'+fixture.stem,base+['-unittest',fixture])
        for fixture in negatives:run(name+'-'+fixture,base+[fixtures/fixture],True)
    run('ldc-wasm-betterc-contracts',[a.ldc,'-c','-o-','-preview=dip1000','-betterC','-mtriple=wasm32-unknown-unknown-wasm','-Icontracts/source','contracts/source/flint/wasm_bridge.d','contracts/source/flint/ui_signals.d'])
    payload={'verified_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Semantic/type checking of declaration contracts, real main/usage/unittest fixture bodies, explicit @nogc/nothrow lifecycle and borrowing compile-fails. No framework implementation linkage, runtime benchmark or non-Linux execution is implied.','source_sha256':{m:hashlib.sha256((root/m).read_bytes()).hexdigest() for m in modules},'checks':checks,'passed':all(x['passed'] for x in checks)}
    (root/a.out).write_text(json.dumps(payload,indent=2)+'\n')
    raise SystemExit(0 if payload['passed'] else 1)
if __name__=='__main__':main()
