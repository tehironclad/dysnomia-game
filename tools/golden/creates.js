#!/usr/bin/env node
// The Dysnomia deployer's future CREATE addresses (keccak256(rlp([sender, nonce]))),
// computed with entropy-ai-pulse's own api/lib/keccak.js. The game has no keccak,
// so World watch checks eth_getCode at these addresses for every nonce the
// deployer has used past the baseline. A find is still verified on-chain
// (bytecode selectors + wiring) before anything reads "live".
//
// Usage: node tools/golden/creates.js <path-to-entropy-ai-pulse> [from=700] [to=1200]
'use strict';
const fs = require('fs');
const path = require('path');
const [, , repo, fromArg, toArg] = process.argv;
if (!repo) { console.error('usage: node tools/golden/creates.js <entropy-ai-pulse> [from] [to]'); process.exit(2); }
const k = require(path.resolve(repo, 'api/lib/keccak.js'));
const DEPLOYER = '0x0474606332105a1da6fc8ef7de2470551d389cb9';
const from = Number(fromArg || 700), to = Number(toArg || 1200);
const creates = {};
for (let n = from; n <= to; n++) creates[n] = k.createAddress(DEPLOYER, n).toLowerCase();
const root = path.resolve(__dirname, '..', '..');
fs.writeFileSync(path.join(root, 'assets/data/deployer_creates.json'), JSON.stringify({
  deployer: DEPLOYER, formula: 'keccak256(rlp([deployer, nonce]))[12:]', from, to, creates,
}) + '\n');
console.log(`creates ${from}..${to}; nonce 712 → ${creates[712]}`);
