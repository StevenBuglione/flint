// Executes the actual implementation-backed BetterC fixture for one package.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const path=process.argv[2];assert.ok(path,'pass a linked BetterC fixture .wasm file');
const module=await WebAssembly.compile(fs.readFileSync(path));
assert.deepEqual(WebAssembly.Module.imports(module),[],'BetterC core imported a runtime/host service');
const instance=await WebAssembly.instantiate(module,{});
assert.ok(instance.exports.memory?.buffer instanceof ArrayBuffer,'BetterC requires exported, unshared memory');
assert.equal(typeof instance.exports.flint_test,'function','missing explicit test entry point');
assert.equal(instance.exports.flint_test(),0,'package behavior returned failure');
console.log(JSON.stringify({schema:1,scope:'actual package BetterC WASM assertions',artifact:path,passed:true}));
