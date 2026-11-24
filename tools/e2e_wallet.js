#!/usr/bin/env node
// The browser half of the wallet end-to-end harness. Run: tools/e2e_wallet.sh
//
// 1. Starts Godot headless on tools/e2e_wallet.gd: the real Wallet autoload and
//    WalletBridge serve the real assets/web/wallet.html (with its session token).
// 2. Opens that page in Chromium (Playwright) the way a player's browser does,
//    with a mock EIP-1193 wallet injected as window.ethereum and announced over
//    EIP-6963 (like Rabby / MetaMask). The mock records every request and answers
//    like a strict real wallet: accounts (mixed case), chain 0x1 at first (refuses the
//    first switch to 0x171, accepts the next), and for eth_sendTransaction a REAL past
//    AFFECTION transfer hash from that account to that QING, so the game's
//    wait_receipt/verify_receipt run against a real receipt. Nothing is broadcast.
// 3. Window cases: a page from an earlier game session (old token) reloads itself;
//    a second window is turned away; later the window is closed and a payment
//    reopens/relinks it.
// 4. Checks the game's results (results.json) and the requests the wallet saw.
//
// Usage: node tools/e2e_wallet.js [--godot=godot] [--port=48420] [--keep]
'use strict';
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.slice(n.length + 3) : d; };
const GODOT = arg('godot', process.env.GODOT || 'godot');
const PORT = +arg('port', 48420);
// A real AFFECTION transfer: 2 Ⓐ from WALLET to the QING "QING" in block 27,788,018
// (found with eth_getLogs on AFFECTION Transfer to a QING; the wallet still holds Ⓐ,
// so the game's simulations from it succeed at the latest block).
const WALLET = arg('wallet', '0xb644ba4797c8eab1c5a33c41e00096eb4e06d465');
const QING = arg('qing', '0x299c56d1e1efa1d662823faa7fe7ccda6a4f35eb');
const HASH = arg('hash', '0x4a556d285461e5a01d1c857b12efcc5d6f13ce6ae9daaf44b8a7fbb6c0658f3b');
const AFFECTION = '0x24f0154c1dce548adf15da2098fdd8b8a3b8151d';
const FAKE_SIG = '0x' + 'ab'.repeat(32) + 'cd'.repeat(32) + '1b';
// The account as a wallet reports it: mixed case (the game must not care)
const MIXED = '0x' + WALLET.slice(2).split('').map((c, i) => (i % 3 === 0 ? c.toUpperCase() : c)).join('');

const ctl = fs.mkdtempSync(path.join(os.tmpdir(), 'dys-e2e-'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFile(name, ms) {
  const t0 = Date.now();
  while (!fs.existsSync(path.join(ctl, name))) {
    if (Date.now() - t0 > ms) throw new Error('timed out waiting for ' + name);
    await sleep(100);
  }
}

// ---- The mock wallet: state and decisions live here (shared by every page) ----
const calls = [];
const st = { chain: '0x1', switches: 0, txs: 0 };
const STRICT_QTY = /^0x(0|[1-9a-f][0-9a-f]*)$/;
async function decide(pageName, method, params) {
  calls.push({ page: pageName, method, params, t: Date.now() });
  switch (method) {
    case 'eth_requestAccounts':
    case 'eth_accounts':
      return { result: [MIXED] };
    case 'eth_chainId':
      return { result: st.chain };
    case 'wallet_switchEthereumChain': {
      st.switches++;
      if (st.switches === 1) return { error: { code: 4001, message: 'User rejected the request.' } };
      st.chain = params[0].chainId;
      return { result: null, emit: ['chainChanged', st.chain] };
    }
    case 'wallet_addEthereumChain':
      return { result: null };
    case 'eth_sendTransaction': {
      st.txs++;
      const tx = params[0] || {};
      // What strict wallets reject: a non-quantity value/gas, a missing or wrong chainId, a foreign from
      const bad = [];
      if (String(tx.from).toLowerCase() !== WALLET) bad.push('from ' + tx.from);
      if (tx.chainId !== undefined && tx.chainId !== st.chain) bad.push('chainId ' + tx.chainId + ' while on ' + st.chain);
      if (tx.value !== undefined && (typeof tx.value !== 'string' || !STRICT_QTY.test(tx.value))) bad.push('value ' + JSON.stringify(tx.value));
      if (tx.gas !== undefined && (typeof tx.gas !== 'string' || !STRICT_QTY.test(tx.gas))) bad.push('gas ' + JSON.stringify(tx.gas));
      if (!/^0x[0-9a-f]*$/i.test(String(tx.data))) bad.push('data');
      if (st.chain !== '0x171') bad.push('sent while the wallet is on ' + st.chain);
      if (bad.length) return { error: { code: -32602, message: 'Invalid params: ' + bad.join(', ') } };
      if (st.txs === 3) return { error: { code: 4001, message: 'User rejected the request.' } };
      if (st.txs === 4) await sleep(3000);
      return { result: HASH };
    }
    case 'personal_sign':
      return { result: FAKE_SIG };
    default:
      return { error: { code: 4200, message: 'Unsupported method ' + method } };
  }
}

// Injected before the page's own script (like an extension's content script)
function mockWallet() {
  const listeners = {};
  const provider = {
    isRabby: true, isMetaMask: true,
    request: async ({ method, params }) => {
      const d = await window.__wallet(method, params || []);
      if (d.emit) setTimeout(() => (listeners[d.emit[0]] || []).forEach((f) => f(d.emit[1])), 10);
      if (d.error) { const e = new Error(d.error.message); e.code = d.error.code; throw e; }
      return d.result;
    },
    on: (ev, f) => { (listeners[ev] = listeners[ev] || []).push(f); },
    removeListener: (ev, f) => { listeners[ev] = (listeners[ev] || []).filter((g) => g !== f); },
  };
  window.ethereum = provider;
  const info = { uuid: 'e2e-mock-0001', name: 'Mock Rabby', icon: 'data:,', rdns: 'io.rabby.e2e' };
  const announce = () => window.dispatchEvent(new CustomEvent('eip6963:announceProvider', { detail: Object.freeze({ info, provider }) }));
  window.addEventListener('eip6963:requestProvider', announce);
  announce();
}

async function main() {
  const logPath = path.join(ctl, 'godot.log');
  const out = fs.openSync(logPath, 'w');
  const godot = spawn(GODOT, ['--headless', '--path', ROOT, '-s', 'res://tools/e2e_wallet.gd', '--',
    '--port=' + PORT, '--ctl=' + ctl, '--wallet=' + WALLET, '--qing=' + QING, '--hash=' + HASH], { stdio: ['ignore', out, out] });
  const exited = new Promise((res) => godot.on('exit', (code) => res(code)));
  let browser;
  const problems = [];
  const expect = (ok, what) => { console.log((ok ? 'PASS ' : 'FAIL ') + what); if (!ok) problems.push(what); };
  try {
    await waitFile('ready', 60000);
    const port = +fs.readFileSync(path.join(ctl, 'ready'), 'utf8');
    const url = 'http://localhost:' + port + '/';
    browser = await chromium.launch();
    const context = await browser.newContext();
    let pageNo = 0;
    const newPage = async (name) => {
      const p = await context.newPage();
      await p.exposeFunction('__wallet', (m, prm) => decide(name, m, prm));
      await p.addInitScript(mockWallet);
      p.on('console', (m) => { if (m.type() === 'error') console.log('  [' + name + ' console] ' + m.text()); });
      p.__name = name;
      pageNo++;
      return p;
    };

    // A: a window left open from an earlier game session: its first hello carries an
    // old token (patched on the wire, once per tab); the page must reload and link.
    const a = await newPage('A');
    let staleServed = false;
    await a.exposeFunction('__staleMark', () => { staleServed = true; });
    await a.addInitScript(() => {
      if (sessionStorage.getItem('e2e.stale')) return;
      sessionStorage.setItem('e2e.stale', '1');
      const orig = WebSocket.prototype.send;
      WebSocket.prototype.send = function (d) {
        try {
          const m = JSON.parse(d);
          if (m.type === 'hello') { m.token = '0'.repeat(32); d = JSON.stringify(m); window.__staleMark(); }
        } catch (e) { /* not JSON */ }
        return orig.call(this, d);
      };
    });
    await a.goto(url);
    await a.waitForFunction(() => /Connected:/.test(document.getElementById('status').textContent), null, { timeout: 30000 });
    expect(staleServed, 'the first hello carried an old token (a window from an earlier session)');
    expect(calls.some((c) => c.page === 'A' && c.method === 'eth_requestAccounts'), 'page A reloaded itself, linked and asked eth_requestAccounts');
    expect(calls.some((c) => c.method === 'wallet_switchEthereumChain' && c.params[0].chainId === '0x171'), 'the page asked the wallet to switch to 0x171');

    // B: a second window while A is linked: turned away, A keeps the link
    const b = await newPage('B');
    await b.goto(url);
    await b.waitForFunction(() => /already linked/.test(document.getElementById('status').textContent), null, { timeout: 15000 });
    expect(true, 'a second window is told another one is linked');
    expect(await b.title() === 'Dysnomia Wallet Bridge (closed)', 'the second window renames itself (focus never raises it)');
    fs.writeFileSync(path.join(ctl, 'go'), '1');

    // Later: the game asks to close A, then a payment waits for a new window C
    await waitFile('close_a', 300000);
    await a.close();
    await waitFile('open_c', 60000);
    await sleep(2000);
    const c = await newPage('C');
    await c.goto(url);

    await waitFile('done', 300000);
    const code = await exited;
    const res = JSON.parse(fs.readFileSync(path.join(ctl, 'results.json'), 'utf8'));
    for (const r of res.results) expect(r.ok, 'game: ' + r.name + (r.ok ? '' : ' → ' + JSON.stringify(r)));
    if (res.error) expect(false, 'game: ' + res.error);
    expect(code === 0, 'godot exited 0 (got ' + code + ')');

    // What the wallet saw
    const sends = calls.filter((c2) => c2.method === 'eth_sendTransaction').map((c2) => c2.params[0]);
    const pad = (h) => h.replace(/^0x/, '').padStart(64, '0');
    const fair = res.results.find((r) => r.name === 'fair ticket') || {};
    const fee = BigInt(fair.fee_wei || '0');
    expect(fee > 10n ** 18n && fee <= 10n ** 18n + 7n, 'the fair fee is 1 Ⓐ + a 1..7 wei code (' + fee + ')');
    const wantFair = '0xa9059cbb' + pad(QING) + pad(fee.toString(16));
    const wantArcade = '0xa9059cbb' + pad(QING) + pad((10n ** 18n).toString(16));
    expect(sends.length === 5, 'exactly 5 eth_sendTransaction reached the wallet (got ' + sends.length + '; the reverting one must not)');
    const s0 = sends[0] || {};
    expect(s0.from === WALLET && s0.to === AFFECTION && s0.data === wantFair, 'fair ticket params: from, to = AFFECTION, data = transfer(QING, 1e18+k)');
    expect(s0.chainId === '0x171' && s0.value === undefined && s0.gas === undefined, 'fair ticket: chainId 0x171, no value, no gas (the wallet estimates)');
    expect((sends[1] || {}).data === wantArcade, 'arcade credit data = transfer(QING, 1e18)');
    expect(sends.slice(2).every((x) => x.data === wantFair), 'the later tickets carry the same fair calldata');
    const sw = calls.filter((c2) => c2.method === 'wallet_switchEthereumChain');
    expect(sw.length >= 2, 'refused switch at connect, then the payment asked again (' + sw.length + ' switch requests)');
    const firstSend = calls.findIndex((c2) => c2.method === 'eth_sendTransaction');
    const okSwitch = calls.findIndex((c2, i) => c2.method === 'wallet_switchEthereumChain' && i > calls.findIndex((x) => x.method === 'wallet_switchEthereumChain'));
    expect(okSwitch >= 0 && okSwitch < firstSend, 'the chain was switched before the first eth_sendTransaction');
    const ps = calls.find((c2) => c2.method === 'personal_sign');
    const signRes = res.results.find((r) => r.name === 'personal_sign') || {};
    const msgHex = '0x' + Buffer.from(signRes.message || '', 'utf8').toString('hex');
    expect(ps && ps.params[0] === msgHex && String(ps.params[1]).toLowerCase() === WALLET, 'personal_sign params = [utf-8 hex of the message, account]');
    expect(signRes.signature === FAKE_SIG, 'the signature came back unchanged');
    expect(calls.filter((c2) => c2.method === 'eth_sendTransaction').every((c2) => c2.page !== 'B'), 'the turned-away window B never got a request');
    expect(calls.some((c2) => c2.page === 'C' && c2.method === 'eth_sendTransaction'), 'the reopened window C handled the last payment');
  } catch (e) {
    expect(false, 'harness: ' + (e && e.stack || e));
  } finally {
    if (browser) await browser.close();
    if (godot.exitCode === null) godot.kill('SIGKILL');
  }
  const log = fs.readFileSync(logPath, 'utf8').split('\n').filter((l) => /\[(Pay|E2E|WalletBridge)\]|SCRIPT ERROR|ERROR:/.test(l));
  console.log('\n--- game log ([Pay]/[E2E]/[WalletBridge]/errors) ---\n' + log.join('\n'));
  console.log('\n' + (problems.length ? problems.length + ' check(s) FAILED' : 'all checks passed') + ' · control dir ' + ctl);
  if (!process.argv.includes('--keep') && !problems.length) fs.rmSync(ctl, { recursive: true, force: true });
  process.exit(problems.length ? 1 : 0);
}
main();
