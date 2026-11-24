// Golden vectors for Keccak-256, personal_sign and ecrecover (tests/test_net_crypto.gd).
// Usage: node tools/golden/ecrecover.js <dir with node_modules/ethers (v6)>
// Writes tests/golden/ecrecover.json. The keys are throwaway test keys, never a player's.
const path = require('path');
const fs = require('fs');
const ethers = require(path.join(process.argv[2] || '.', 'node_modules', 'ethers'));
const keccak = [];
const inputs = ['', 'abc', 'Dysnomia', 'x'.repeat(135), 'y'.repeat(136), 'z'.repeat(137), 'é∑ unicode ✓ '.repeat(30)];
for (const s of inputs) keccak.push({ text: s, hash: ethers.keccak256(ethers.toUtf8Bytes(s)) });
const keys = [
  '0x0000000000000000000000000000000000000000000000000000000000000001',
  '0x0000000000000000000000000000000000000000000000000000000000000002',
  '0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318',
  '0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140',
  ethers.keccak256(ethers.toUtf8Bytes('dysnomia test wallet A')),
  ethers.keccak256(ethers.toUtf8Bytes('dysnomia test wallet B')),
];
const messages = ['hello', 'Dysnomia game server login\nServer: test\nNonce: 00112233445566778899aabbccddeeff', ''];
const signatures = [];
for (const k of keys) {
  const w = new ethers.Wallet(k);
  for (const m of messages) {
    const sig = w.signMessageSync(m);
    signatures.push({ key: k, address: w.address.toLowerCase(), message: m, hash: ethers.hashMessage(m), signature: sig });
  }
}
const out = { generator: 'tools/golden/ecrecover.js (ethers ' + ethers.version + ')', keccak, signatures };
fs.writeFileSync(path.join(__dirname, '..', '..', 'tests', 'golden', 'ecrecover.json'), JSON.stringify(out, null, 1) + '\n');
console.log('wrote', keccak.length, 'keccak and', signatures.length, 'signature vectors');
