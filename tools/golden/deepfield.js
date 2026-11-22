#!/usr/bin/env node
// Golden vectors for the GDScript Deep Field port (scripts/deepfield/deep_field.gd).
//
// Usage: node tools/golden/deepfield.js <path-to-entropy-ai-pulse>
// Reads assets/data/territories.json, runs the site's own lib/deep-field.js and
// writes tests/golden/deepfield.json:
//   territories: params for every territory (number = entropy, address = QING)
//   identities:  params for 60 identities (number = Aura(address), address = wallet)
//   dives:       divePoint for the first 60 power-2 territories
//   renders:     small RGB renders (hex) for one territory per style, for the CPU port
'use strict';
const fs = require('fs');
const path = require('path');

const repo = process.argv[2];
if (!repo) {
  console.error('usage: node tools/golden/deepfield.js <entropy-ai-pulse>');
  process.exit(2);
}
const DF = require(path.resolve(repo, 'lib/deep-field.js'));
const root = path.resolve(__dirname, '..', '..');
const snap = JSON.parse(fs.readFileSync(path.join(root, 'assets/data/territories.json'), 'utf8'));

const pick = (p) => ({
  c: p.c, family: p.family, arms: p.arms, turn: p.turn, depth: p.depth, power: p.power,
  tier: p.tier, style: p.style, rotation: p.rotation, hue: p.hue, color: p.color,
  color2: p.color2, extent: p.extent, frame: p.frame,
});

const territories = snap.territories.map((q) => ({
  address: q.address, number: q.entropy, p: pick(DF.params(q.entropy, q.address)),
}));

// Identities: any addresses work as "wallets"; use the asset tokens (distinct, real).
const wallets = [...new Set(snap.territories.map((q) => q.asset).filter(Boolean))].slice(0, 60);
const identities = wallets.map((w) => {
  const aura = DF.aura(w).toString();
  return { address: w, aura, p: pick(DF.params(aura, w)) };
});

const dives = [];
for (const q of snap.territories) {
  const p = DF.params(q.entropy, q.address);
  if (p.power !== 2) continue;
  const d = DF.divePoint(p, q.address);
  dives.push({ address: q.address, number: q.entropy, z: d.z, mag: d.mag, arg: d.arg, period: d.period });
  if (dives.length >= 60) break;
}

// One render per style (plus a high-power one), 24×24, maxIter 160.
const W = 24, H = 24;
const renders = [];
const wanted = new Set(['glow', 'duo', 'bands', 'ember', 'gilded', 'prism']);
for (const q of snap.territories) {
  const p = DF.params(q.entropy, q.address);
  if (!wanted.has(p.style)) continue;
  wanted.delete(p.style);
  const out = new Uint8ClampedArray(W * H * 4);
  DF.render(out, W, H, p, {});
  const rgb = [];
  for (let i = 0; i < W * H; i++) rgb.push(out[i * 4], out[i * 4 + 1], out[i * 4 + 2]);
  renders.push({ address: q.address, number: q.entropy, style: p.style, power: p.power, w: W, h: H,
    rgb: Buffer.from(rgb).toString('hex') });
}

fs.writeFileSync(path.join(root, 'tests/golden/deepfield.json'),
  JSON.stringify({ source: 'entropy-ai-pulse lib/deep-field.js', territories, identities, dives, renders }) + '\n');
const tiers = {};
territories.forEach((t) => { tiers[t.p.tier] = (tiers[t.p.tier] || 0) + 1; });
console.log(`territories ${territories.length}, identities ${identities.length}, dives ${dives.length}, ` +
  `renders ${renders.length} (${renders.map((r) => r.style).join(',')}); tiers ${JSON.stringify(tiers)}`);
