import fs from 'node:fs';
import assert from 'node:assert/strict';
import {decodeBatch} from '../../templates/golden-wasm-app/driver.mjs';
const {instance}=await WebAssembly.instantiate(fs.readFileSync(process.argv[2]),{});
const x=instance.exports,results=[];
function check(name,body) { body();results.push({name,passed:true}); }
function reset() {const length=x.probe_build(),pointer=x.probe_pointer();return {length,pointer,view:new DataView(x.memory.buffer)};}
check('real WASM emits a valid text record',()=>{
    const {length,pointer}=reset();assert.equal(length,56);const decoded=decodeBatch(x.memory,pointer,length);
    assert.equal(decoded.operations[0].text,'42');assert.equal(decoded.operations.length,1);
});
check('oversized record rejected',()=>{
    const {length,pointer,view}=reset();view.setUint32(pointer+36,0xfffffff8,true);
    assert.throws(()=>decodeBatch(x.memory,pointer,length),/record size/);
});
check('unknown opcode rejected',()=>{
    const {length,pointer,view}=reset();view.setUint16(pointer+32,99,true);
    assert.throws(()=>decodeBatch(x.memory,pointer,length),/unknown opcode/);
});
check('stale node generation rejected',()=>{
    const {length,pointer,view}=reset();view.setUint32(pointer+44,2,true);
    assert.throws(()=>decodeBatch(x.memory,pointer,length),/stale node/);
});
check('invalid UTF8 rejected',()=>{
    const {length,pointer,view}=reset();view.setUint8(pointer+52,255);
    assert.throws(()=>decodeBatch(x.memory,pointer,length));
});
check('nonzero record padding rejected',()=>{
    const {length,pointer,view}=reset();view.setUint8(pointer+55,1);
    assert.throws(()=>decodeBatch(x.memory,pointer,length),/padding/);
});
check('memory growth recreates host views',()=>{
    const {length,pointer}=reset();x.memory.grow(1);
    assert.equal(decodeBatch(x.memory,pointer,length).operations[0].text,'42');
});
check('pointer outside linear memory rejected',()=>{
    assert.throws(()=>decodeBatch(x.memory,x.memory.buffer.byteLength-3,56),/range/);
});
console.log(JSON.stringify({scope:'standalone linked WASM ABI probe; no Flint runtime implementation',checks:results.length,passed:true,results}));
