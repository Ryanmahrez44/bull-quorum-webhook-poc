// Probe 1: Bull API signature verification (auth binding).
// Fresh wallet generated locally; all state-changing calls use dryRun:true.
// Nothing on-chain, no funds. Run: node auth-probe.mjs
import { createHash } from "crypto";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

const BASE = "https://www.bull.family";
const acct = privateKeyToAccount(generatePrivateKey());
console.log("probe wallet:", acct.address);

const sha = (s) => createHash("sha256").update(s).digest("hex");
async function sign(method, path, ts, bodyRaw) {
  const msg = `Bull API\n${method} ${path}\n${ts}\n${sha(bodyRaw)}`;
  return acct.signMessage({ message: msg });
}
async function req(method, path, { body = null, ts = null, sig = null, addr = null, extraHeaders = {} } = {}) {
  const raw = body === null ? "" : JSON.stringify(body);
  const t = ts ?? Date.now().toString();
  const s = sig ?? (await sign(method, path, t, raw));
  const res = await fetch(BASE + path, {
    method,
    body: raw || undefined,
    headers: {
      "content-type": "application/json",
      "x-bull-address": addr ?? acct.address,
      "x-bull-timestamp": t,
      "x-bull-signature": s,
      ...extraHeaders,
    },
  });
  const j = await res.json().catch(() => ({}));
  return { status: res.status, body: j };
}
const show = (label, r) =>
  console.log(`${label}: HTTP ${r.status} ${JSON.stringify(r.body).slice(0, 300)}`);

const rfqBody = {
  token: "0x30768B5482e5dd8a2487cE0BE61E01fA03Af37ff",
  symbol: "BULL",
  sizeUsd: 5,
  windowMin: 15,
  dryRun: true,
};

// A1: valid signed dryRun create RFQ
const a1 = await req("POST", "/api/v1/rfqs", { body: rfqBody });
show("A1 valid dryRun POST /rfqs", a1);

// A2: exact replay of A1 (same ts, sig, body)
const ts2 = Date.now().toString();
const sig2 = await sign("POST", "/api/v1/rfqs", ts2, JSON.stringify(rfqBody));
const replay = async () => req("POST", "/api/v1/rfqs", { body: rfqBody, ts: ts2, sig: sig2 });
const a2a = await replay();
show("A2a first send (fresh ts)", a2a);
const a2b = await replay();
show("A2b EXACT REPLAY same ts+sig+body", a2b);

// A3: method swap — signature over GET, sent as POST
const ts3 = Date.now().toString();
const sigGet = await sign("GET", "/api/v1/rfqs", ts3, "");
const a3 = await req("POST", "/api/v1/rfqs", { body: rfqBody, ts: ts3, sig: sigGet });
show("A3 GET-sig reused for POST /rfqs", a3);

// A4: path swap — signature over POST /rfqs, sent to POST /rfqs/<id>/quotes
const ts4 = Date.now().toString();
const sig4 = await sign("POST", "/api/v1/rfqs", ts4, JSON.stringify({ tokens: "1", price: "0.01" }));
const a4 = await req("POST", "/api/v1/rfqs/4409e5c8a8e4/quotes", {
  body: { tokens: "1", price: "0.01" },
  ts: ts4,
  sig: sig4,
});
show("A4 POST-/rfqs sig reused for POST /rfqs/:id/quotes", a4);

// A5: body swap — sign body X, send body Y
const ts5 = Date.now().toString();
const sig5 = await sign("POST", "/api/v1/rfqs", ts5, JSON.stringify(rfqBody));
const otherBody = { ...rfqBody, sizeUsd: 500000 };
const a5 = await req("POST", "/api/v1/rfqs", { body: otherBody, ts: ts5, sig: sig5 });
show("A5 sig for sizeUsd=5 sent with sizeUsd=500000", a5);

// A6: stale timestamp (10 min old)
const ts6 = (Date.now() - 10 * 60 * 1000).toString();
const sig6 = await sign("POST", "/api/v1/rfqs", ts6, JSON.stringify(rfqBody));
const a6 = await req("POST", "/api/v1/rfqs", { body: rfqBody, ts: ts6, sig: sig6 });
show("A6 stale ts (-10min)", a6);

// A7: future timestamp (+10 min)
const ts7 = (Date.now() + 10 * 60 * 1000).toString();
const sig7 = await sign("POST", "/api/v1/rfqs", ts7, JSON.stringify(rfqBody));
const a7 = await req("POST", "/api/v1/rfqs", { body: rfqBody, ts: ts7, sig: sig7 });
show("A7 future ts (+10min)", a7);

// A8: address header != signer
const a8 = await req("POST", "/api/v1/rfqs", {
  body: rfqBody,
  addr: "0x1111111111111111111111111111111111111111",
});
show("A8 address header mismatch", a8);

// A9: no signature at all (unsigned dryRun)
const res9 = await fetch(BASE + "/api/v1/rfqs", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(rfqBody),
});
console.log("A9 no auth headers: HTTP", res9.status, JSON.stringify(await res9.json()).slice(0, 200));

// A10: GET-sig for one quote path reused on another GET path (quote status of the public RFQ's quote — unknown id, use dummy)
const ts10 = Date.now().toString();
const sig10 = await sign("GET", "/api/v1/rfqs/4409e5c8a8e4/quotes", ts10, "");
const a10 = await req("GET", "/api/v1/quotes/doesnotexist123", { ts: ts10, sig: sig10 });
show("A10 GET rfqs/:id/quotes sig reused for GET quotes/:id", a10);
