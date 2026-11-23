#!/usr/bin/env node
// Generates golden test vectors and the shipped territory snapshot.
//
// Usage:
//   node tools/golden/gen.js <path-to-entropy-ai-pulse> <path-to-qing-registry.json> [--snapshot]
//
// - tests/golden/selectors.json : keccak-256 selectors/topics for every signature
//   listed in SIGNATURES (computed with entropy-ai-pulse's own api/lib/keccak.js).
// - tests/golden/projection.json: raw HECKE.Compliment words (from the old
//   assets/data/qing_map.json) paired with the site's projected lat/lon.
// - assets/data/territories.json: the territory snapshot the game ships with.
'use strict';
const fs = require('fs');
const path = require('path');

const [, , repo, registryPath] = process.argv;
if (!repo || !registryPath) {
  console.error('usage: node tools/golden/gen.js <entropy-ai-pulse> <qing-registry.json>');
  process.exit(2);
}
const k = require(path.resolve(repo, 'api/lib/keccak.js'));
const keccak = k.keccak256 || k;
const hex = (s) => {
  const h = keccak(s);
  return (typeof h === 'string' ? h : Buffer.from(h).toString('hex')).replace(/^0x/, '');
};

const root = path.resolve(__dirname, '..', '..');

// Every function/event/error signature the game uses. Must mirror scripts/chain/contracts.gd.
const SIGNATURES = {
  functions: [
    'New(string,string)', 'Username(string)', 'Enter(address)', 'Start(address,string,string)',
    'Play(address)', 'Su(address)', 'Chat(address,string)', 'Join(address)', 'Chat(string)',
    'Beat(uint256)', 'approve(address,uint256)', 'transfer(address,uint256)',
    'Alpha(uint64)', 'Beta(uint64)', 'Pi()', 'Rho()', 'Generate()', 'Upsilon(uint64,bool)',
    'Leave()', 'Void(bool,bool)', 'Withdraw(address,uint256)', 'Code(int256,int256,address)',
    'Faa(address,uint256)', 'GetUserTokenAddress(address)', 'Yan(address)', 'Username()',
    'Saat(uint256)', 'Bar(address)', 'Waat()', 'Entropy()', 'Asset()', 'GWAT()', 'CoverCharge()',
    'BouncerDivisor()', 'Admitted(address)', 'Compliment(uint256)', 'GetMapQing(int256,int256)',
    'GetQing(uint256)', 'Offset()', 'Cho()', 'Yuan(address)', 'Eta()', 'balanceOf(address)',
    'totalSupply()', 'decimals()', 'name()', 'symbol()', 'allowance(address,address)',
    'maxSupply()', 'owner(address)', 'aggregate3((address,bool,bytes)[])', 'View()', 'Type()',
  ],
  events: [
    'LogEvent(string,uint64,uint64,string)', 'LogEvent(uint64,uint64,string)',
    'NewQing(address,address,uint256)', 'Transfer(address,address,uint256)',
  ],
  errors: [
    'Error(string)', 'Panic(uint256)', 'NotStarted(address)', 'ZeroHoldings(address)',
    'OutOfRange(int256,int256,uint256)', 'UserNotEntered(address)', 'SoulNotEntered(uint64)',
    'NotAdmitted(uint64)', 'Forbidden(address)', 'CoverChargeUnauthorized(address,uint256)',
    'PayCover(address,uint256)', 'OwnableUnauthorizedAccount(address,address,address)',
    'DysnomiaInsufficientBalance(address,address,address,address,address,uint256,uint256)',
    'DysnomiaInsufficientAllowance(address,address,address,address,address,uint256,uint256)',
  ],
};

const selectors = {};
for (const s of SIGNATURES.functions) selectors[s] = '0x' + hex(s).slice(0, 8);
for (const s of SIGNATURES.errors) selectors[s] = '0x' + hex(s).slice(0, 8);
const topics = {};
for (const s of SIGNATURES.events) topics[s] = '0x' + hex(s);
fs.mkdirSync(path.join(root, 'tests/golden'), { recursive: true });
fs.writeFileSync(path.join(root, 'tests/golden/selectors.json'),
  JSON.stringify({ selectors, topics }, null, 1) + '\n');

// Territory snapshot (only with --snapshot: tools/update_snapshot.gd is the
// normal way to refresh it, and keeps the raw Compliment words) -------------
const writeSnapshot = process.argv.includes('--snapshot');
const reg = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
const qings = reg.qings.map((q) => ({
  address: q.address.toLowerCase(),
  asset: (q.lau || '').toLowerCase(), // the registry's "lau" field is actually the asset token
  waat: q.waat, // decimal string, uint256
  block: q.block,
  name: q.name,
  symbol: q.symbol,
  entropy: q.entropy, // decimal string
  gwat: !!q.gwat,
  cover_charge: q.coverCharge,
  bouncer_divisor: q.bouncerDivisor,
  creator: (q.creator || '').toLowerCase(),
  lat: q.lat,
  lon: q.lon,
}));
qings.sort((a, b) => a.block - b.block || (a.address < b.address ? -1 : 1));
const snapshotBlock = Math.max(...qings.map((q) => q.block));
if (writeSnapshot) fs.writeFileSync(path.join(root, 'assets/data/territories.json'), JSON.stringify({
  source: 'systm0.vercel.app/data/qing-registry.json',
  generated_at: reg.generatedAt,
  snapshot_block: snapshotBlock,
  count: qings.length,
  territories: qings,
}) + '\n');

// Projection golden: old raw words vs site lat/lon --------------------------
const oldMapPath = path.join(root, 'tests/golden/qing_map_legacy.json');
const byAddr = new Map(qings.map((q) => [q.address, q]));
const proj = [];
if (fs.existsSync(oldMapPath)) {
  const old = JSON.parse(fs.readFileSync(oldMapPath, 'utf8'));
  for (const o of old.qings) {
    const r = byAddr.get(o.address.toLowerCase());
    if (r) proj.push({ address: r.address, lon_word: o.lon_hex, lat_word: o.lat_hex, lat: r.lat, lon: r.lon });
  }
  fs.writeFileSync(path.join(root, 'tests/golden/projection.json'), JSON.stringify(proj, null, 0) + '\n');
}
console.log(`selectors ${Object.keys(selectors).length}, topics ${Object.keys(topics).length}, ` +
  `territories ${qings.length} (snapshot block ${snapshotBlock}), projection vectors ${proj.length}`);
