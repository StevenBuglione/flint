// Executes the REAL compiled Flint counter and validates its ABI/signal behavior.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {decodeBatch,initialState} from '../../benchmarks/bench-wasm/driver.mjs';
const path=process.argv[2];assert.ok(path,'pass build/bench-wasm.wasm');
const module=await WebAssembly.compile(fs.readFileSync(path)),results=[];
function check(name,body) {body();results.push({name,passed:true});}
check('browser core has no unexpected runtime imports',()=>assert.deepEqual(WebAssembly.Module.imports(module),[]));
const instance=await WebAssembly.instantiate(module,{}),x=instance.exports;
check('all scalar entry points are exported',()=>{
    for(const name of ['flint_init','flint_tick','flint_buffer_ptr','flint_buffer_len'])assert.equal(typeof x[name],'function');
});
check('linear memory is exported',()=>assert.ok(x.memory instanceof WebAssembly.Memory));
check('zero session epoch is rejected',()=>assert.notEqual(x.flint_init(0),0));
check('valid session initializes',()=>assert.equal(x.flint_init(1),0));
check('second initialization is rejected',()=>assert.notEqual(x.flint_init(1),0));
let state=initialState(1);
function frame(delta,expected) {
    assert.equal(x.flint_tick(delta),0);
    const length=x.flint_buffer_len();assert.ok(length>=32&&length<=65536);
    // decodeBatch enforces active epoch and forward sequence including empty frames.
    const batch=decodeBatch(x.memory,x.flint_buffer_ptr(),length,state);state=batch.state;
    if(expected===null)assert.equal(batch.operations.length,0,'unchanged signal should emit no patch');
    else {assert.equal(batch.operations.length,1);assert.equal(batch.operations[0].opcode,2);assert.equal(batch.operations[0].text,expected);}
}
check('first frame emits initial signal',()=>frame(0,'0'));
check('delta changes the signal',()=>frame(3,'3'));
check('unchanged signal emits no patch',()=>frame(0,null));
check('subsequent frame preserves state',()=>frame(2,'5'));
check('oversized input is rejected',()=>assert.notEqual(x.flint_tick(1025),0));
check('rejected input leaves state unchanged',()=>frame(1,'6'));
check('memory growth preserves signal and refreshes host views',()=>{x.memory.grow(1);frame(1,'7');});
console.log(JSON.stringify({schema:1,scope:'actual Flint WASM counter integration',passed:true,checks:results.length,results}));
