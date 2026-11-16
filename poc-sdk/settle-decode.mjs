// Probe 4: decode the /settle createDeal tx (fee-quote structure: is there a
// signed fee + deadline on-chain?) + validation fuzz on /settle + receipts.
// No tx is ever sent. Run: node settle-decode.mjs
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

const BASE = "https://www.bull.family";
const BULL = "0x30768B5482e5dd8a2487cE0BE61E01fA03Af37ff";
const seller = privateKeyToAccount(generatePrivateKey());
const buyer = privateKeyToAccount(generatePrivateKey());
console.log("seller:", seller.address, "buyer:", buyer.address);

async function post(path, body) {
  const res = await fetch(BASE + path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const j = await res.json().catch(() => ({}));
  return { status: res.status, body: j };
}

// --- decode a real createDeal tx ---
const terms = { buyer: buyer.address, seller: seller.address, sellToken: BULL, sellAmount: "1000", payAsset: "eth", payAmount: "0.25" };
let c1 = await post("/api/v1/settle", { ...terms, consentOnly: true });
if (c1.status !== 200) {
  console.log("c1 retry after rate limit, got:", c1.status, JSON.stringify(c1.body).slice(0, 200));
  await new Promise((r) => setTimeout(r, 8000));
  c1 = await post("/api/v1/settle", { ...terms, consentOnly: true });
}
console.log("c1:", c1.status, JSON.stringify(c1.body).slice(0, 200));
const sig = await seller.signMessage({ message: c1.body.message });
const c2 = await post("/api/v1/settle", { ...terms, sellerSig: sig, validUntil: c1.body.validUntil });
console.log("\nD1 control /settle:", c2.status, "feeBps:", c2.body.feeBps, "feeUsd:", c2.body.feeUsd);
console.log("full body keys:", Object.keys(c2.body));
console.log("tx:", JSON.stringify(c2.body.transaction, null, 1).slice(0, 1500));
const data = c2.body.transaction.data;
console.log("data len bytes:", (data.length - 2) / 2, "selector:", data.slice(0, 10));
const words = [];
for (let i = 10; i + 64 <= data.length; i += 64) words.push(data.slice(i, i + 64));
words.forEach((w, i) => {
  const asAddr = "0x" + w.slice(24);
  const asNum = BigInt("0x" + w).toString();
  console.log(`  w${i}: ${w}  num=${asNum} addr?=${asAddr}`);
});
if ((data.length - 2) % 2 === 1 || (data.length - 10) % 64 !== 0)
  console.log("  trailing bytes (not word-aligned):", data.slice(10 + words.length * 64));

// --- validation fuzz on /settle consentOnly (read-only: only returns messages) ---
const fuzz = [
  ["F1 sellAmount 0", { ...terms, sellAmount: "0" }],
  ["F2 payAmount 0", { ...terms, payAmount: "0" }],
  ["F3 payAmount huge 1e9", { ...terms, payAmount: "1000000000" }],
  ["F4 deadlineHours 0", { ...terms, deadlineHours: 0 }],
  ["F5 deadlineHours 99999", { ...terms, deadlineHours: 99999 }],
  ["F6 payAsset btc", { ...terms, payAsset: "btc" }],
  ["F7 sellToken zero", { ...terms, sellToken: "0x0000000000000000000000000000000000000000" }],
  ["F8 sellToken escrow", { ...terms, sellToken: "0xd685d39E7a3deF19E52B9AB09679b7452C23e20b" }],
  ["F9 seller==buyer", { ...terms, seller: buyer.address }],
  ["F10 sellAmount abc", { ...terms, sellAmount: "abc" }],
  ["F11 payAmount -1", { ...terms, payAmount: "-1" }],
  ["F12 sellAmount 1e-9 tiny", { ...terms, sellAmount: "0.000000001" }],
];
for (const [label, b] of fuzz) {
  const r = await post("/api/v1/settle", { ...b, consentOnly: true });
  console.log(`${label}: HTTP ${r.status} ${JSON.stringify(r.body).slice(0, 220)}`);
  await new Promise((r2) => setTimeout(r2, 1200));
}

// --- agreements validation fuzz (no auth; returns txs only) ---
const agr = [
  ["G1 empty conditions", { payer: buyer.address, payee: seller.address, asset: "eth", amount: "1", conditions: [] }],
  ["G2 9 conditions", { payer: buyer.address, payee: seller.address, asset: "eth", amount: "1", conditions: Array(9).fill({ type: "time_after", afterHours: 1 }) }],
  ["G3 attest by zero", { payer: buyer.address, payee: seller.address, asset: "eth", amount: "1", conditions: [{ type: "attest", by: "0x0000000000000000000000000000000000000000" }] }],
  ["G4 unknown type", { payer: buyer.address, payee: seller.address, asset: "eth", amount: "1", conditions: [{ type: "teleport", by: buyer.address }] }],
  ["G5 amount 0", { payer: buyer.address, payee: seller.address, asset: "eth", amount: "0", conditions: [{ type: "time_after", afterHours: 1 }] }],
  ["G6 expiry 0", { payer: buyer.address, payee: seller.address, asset: "eth", amount: "1", expiryHours: 0, conditions: [{ type: "time_after", afterHours: 1 }] }],
  ["G7 payee==payer", { payer: buyer.address, payee: buyer.address, asset: "eth", amount: "1", conditions: [{ type: "time_after", afterHours: 1 }] }],
];
for (const [label, b] of agr) {
  const r = await post("/api/v1/agreements", b);
  console.log(`${label}: HTTP ${r.status} ${JSON.stringify(r.body).slice(0, 220)}`);
  await new Promise((r2) => setTimeout(r2, 1200));
}

// --- receipts for nonexistent / unsettled deals ---
for (const id of ["999999", "2", "0", "abc"]) {
  const res = await fetch(`${BASE}/api/v1/receipts/${id}`);
  console.log(`receipt ${id}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  await new Promise((r2) => setTimeout(r2, 800));
}
for (const id of ["999999", "abc"]) {
  const res = await fetch(`${BASE}/api/v1/deals/${id}`);
  console.log(`deal ${id}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
}
