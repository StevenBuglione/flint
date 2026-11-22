// Executable host-driver contract tests; no framework implementation is substituted.
import assert from 'node:assert/strict';
import {decodeBatch,initialState,createDriver} from '../../templates/golden-wasm-app/driver.mjs';
const results=[];
function check(name,body) { body();results.push({name,passed:true}); }
function bytes(size,write) { const buffer=new ArrayBuffer(size);write(new DataView(buffer));return new Uint8Array(buffer); }
function record(opcode,id,generation,payload=new Uint8Array()) {
    const size=Math.ceil((16+payload.length)/8)*8;
    const value=bytes(size,d=>{d.setUint16(0,opcode,true);d.setUint32(4,size,true);d.setUint32(8,id,true);d.setUint32(12,generation,true);});
    value.set(payload,16);return value;
}
function frame(records=[],{sequence=1,epoch=1}={}) {
    const length=32+records.reduce((sum,item)=>sum+item.length,0);
    const value=bytes(length,d=>{d.setUint32(0,0x544e4c46,true);d.setUint16(4,1,true);d.setUint32(8,length,true);
        d.setUint32(12,records.length,true);d.setUint32(16,sequence,true);d.setUint32(20,epoch,true);});
    let offset=32;for(const item of records){value.set(item,offset);offset+=item.length;}
    return {buffer:value.buffer};
}
const create=(id,tag=1,generation=1)=>record(1,id,generation,bytes(4,d=>d.setUint16(0,tag,true)));
const append=(parent,child)=>record(4,parent,1,bytes(8,d=>{d.setUint32(0,child,true);d.setUint32(4,1,true);}));
function text(id,value) {
    const encoded=new TextEncoder().encode(value),payload=bytes(4+encoded.length,d=>d.setUint32(0,encoded.length,true));
    payload.set(encoded,4);return record(2,id,1,payload);
}
const rectangle=(id,x,y,width,height)=>record(6,id,1,bytes(24,d=>{
    d.setUint32(0,1,true);d.setInt32(4,x,true);d.setInt32(8,y,true);d.setUint32(12,width,true);d.setUint32(16,height,true);d.setUint32(20,0x804020ff,true);
}));
const decode=(memory,state=initialState(),capabilities={})=>decodeBatch(memory,0,memory.buffer.byteLength,state,capabilities);
check('empty batch preserves active epoch',()=>assert.equal(decode(frame()).state.epoch,1));
check('zero active epoch rejected',()=>assert.throws(()=>initialState(0),/epoch/));
check('zero incoming epoch rejected',()=>assert.throws(()=>decode(frame([],{epoch:0})),/epoch/));
check('higher incoming epoch cannot reset session',()=>assert.throws(()=>decode(frame([],{epoch:100})),/epoch/));
check('host explicitly chooses a session epoch',()=>assert.equal(decode(frame([],{epoch:42}),initialState(42)).epoch,42));
check('duplicate sequence rejected',()=>{
    const state=decode(frame([],{sequence:3})).state;assert.throws(()=>decode(frame([],{sequence:3}),state),/replayed/);
});
check('out-of-order sequence rejected',()=>{
    const state=decode(frame([],{sequence:3})).state;assert.throws(()=>decode(frame([],{sequence:2}),state),/out-of-order/);
});
check('sequence wrap accepted with forward serial arithmetic',()=>{
    let state=decode(frame([],{sequence:0xfffffffe})).state;
    state=decode(frame([],{sequence:0xffffffff}),state).state;
    assert.equal(decode(frame([],{sequence:0}),state).sequence,0);
});
check('half-range sequence jump rejected',()=>{
    const state=decode(frame([],{sequence:0})).state;assert.throws(()=>decode(frame([],{sequence:0x80000000}),state),/out-of-order/);
});
check('canvas rectangle at final pixel accepted',()=>{
    const result=decode(frame([create(1,5),append(0,1),rectangle(1,299,149,1,1)]),initialState(),{canvas:true});
    assert.equal(result.operations.length,3);
});
check('canvas rectangle exceeding actual dimensions rejected',()=>{
    assert.throws(()=>decode(frame([create(1,5),rectangle(1,10000,10000,16384,16384)]),initialState(),{canvas:true}),/canvas bounds/);
});
check('unavailable canvas capability rejected',()=>{
    assert.throws(()=>decode(frame([create(1,5),rectangle(1,0,0,1,1)])),/canvas unavailable/);
});
check('detached construction can subsequently join mount',()=>{
    const state=decode(frame([create(1),create(2,2),append(1,2),append(0,1)])).state;
    assert.equal(state.nodes.get(1).parent,0);assert.equal(state.nodes.get(2).parent,1);
});
check('mounted subtree cannot move under a detached node',()=>{
    assert.throws(()=>decode(frame([create(1),append(0,1),create(2),append(2,1)])),/leaves mount/);
});
check('node removal increments generation',()=>{
    const state=decode(frame([create(1),append(0,1),record(5,1,1),create(1,1,2)])).state;
    assert.equal(state.nodes.get(1).generation,2);
});
check('retired generation cannot be reused',()=>{
    assert.throws(()=>decode(frame([create(1),record(5,1,1),create(1)])),/retired create/);
});
function chain(first,count,parent) {
    const records=[];for(let i=0;i<count;i++){const id=first+i;records.push(create(id));if(i||parent!==null)records.push(append(i?id-1:parent,id));}
    return records;
}
check('depth64 is accepted',()=>assert.equal(decode(frame(chain(1,64,0))).state.nodes.size,65));
check('depth65 is rejected',()=>assert.throws(()=>decode(frame(chain(1,65,0))),/node depth/));
check('reparent validates full moved subtree depth',()=>{
    assert.throws(()=>decode(frame([...chain(1,32,0),...chain(100,33,null),append(32,100)])),/node depth/);
});
check('invalid second operation causes no DOM mutation',()=>{
    const mount={textContent:'unchanged'},driver=createDriver(mount),memory=frame([text(0,'changed'),record(99,0,1)]);
    assert.throws(()=>driver.apply(memory,0,memory.buffer.byteLength),/unknown opcode/);assert.equal(mount.textContent,'unchanged');
});
check('driver commits sequence only after successful application',()=>{
    const mount={textContent:'original'},driver=createDriver(mount),memory=frame([text(0,'updated')]);
    assert.equal(driver.apply(memory,0,memory.buffer.byteLength),1);assert.equal(mount.textContent,'updated');
    assert.throws(()=>driver.apply(memory,0,memory.buffer.byteLength),/replayed/);
});
if(typeof SharedArrayBuffer!=='undefined')check('shared memory rejected by ABIv1',()=>{
    assert.throws(()=>decodeBatch({buffer:new SharedArrayBuffer(32)},0,32),/shared memory/);
});
console.log(JSON.stringify({scope:'host-side ABI/DOM-driver validation; no Flint runtime implementation',passed:true,checks:results.length,results}));
