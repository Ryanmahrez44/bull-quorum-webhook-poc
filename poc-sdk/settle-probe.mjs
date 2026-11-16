// Probe 2: /settle seller-consent binding.
// Q: is sellerSig bound to the exact deal terms, the seller, and validUntil?
// All wallets fresh + local. No tx is ever sent; we only inspect the tx the
// server RETURNS. Run: node settle-probe.mjs
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

const BASE = "https://www.bull.family";
const BULL = "0x30768B5482e5dd8a2487cE0BE61E01fA03Af37ff"; // BULL token (from public RFQ)
const seller = privateKeyToAccount(generatePrivateKey());
const buyer = privateKeyToAccount(generatePrivateKey());
const attacker = privateKeyToAccount(generatePrivateKey());
console.log("seller:", seller.address, "\nbuyer :", buyer.address, "\nattacker:", attacker.address);

async function post(path, body) {
  const res = await fetch(BASE + path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const j = await res.json().catch(() => ({}));
  return { status: res.status, body: j };
}
const show = (label, r) =>
  console.log(`\n${label}: HTTP ${r.status}\n${JSON.stringify(r.body).slice(0, 600)}`);

const terms = {
  buyer: buyer.address,
  seller: seller.address,
  sellToken: BULL,
  sellAmount: "1000",
  payAsset: "eth",
  payAmount: "0.25",
};

// S1: consentOnly -> message + validUntil
const s1 = await post("/api/v1/settle", { ...terms, consentOnly: true });
show("S1 consentOnly (seller consent message)", s1);
const message = s1.body.message;
const validUntil = s1.body.validUntil;
console.log("\nconsent message:\n" + message);
console.log("validUntil:", validUntil, "now:", Math.floor(Date.now() / 1000));

// Seller signs exactly that message
const sellerSig = await seller.signMessage({ message });
console.log("sellerSig:", sellerSig.slice(0, 20) + "...");

// S2: control — same terms + sellerSig -> expect signed createDeal tx
const s2 = await post("/api/v1/settle", { ...terms, sellerSig, validUntil });
show("S2 CONTROL same terms + sellerSig", s2);

// S3: ATTACK — same sellerSig, payAmount 20x (0.25 -> 5 ETH)
const s3 = await post("/api/v1/settle", { ...terms, payAmount: "5", sellerSig, validUntil });
show("S3 ATTACK same sig, payAmount 0.25 -> 5", s3);

// S4: ATTACK — same sellerSig, sellAmount 1000 -> 100 (seller delivers less, same pay)
const s4 = await post("/api/v1/settle", { ...terms, sellAmount: "100", sellerSig, validUntil });
show("S4 ATTACK same sig, sellAmount 1000 -> 100", s4);

// S5: ATTACK — same sellerSig, sellerPayout redirected to attacker
const s5 = await post("/api/v1/settle", { ...terms, sellerPayout: attacker.address, sellerSig, validUntil });
show("S5 ATTACK same sig, sellerPayout -> attacker", s5);

// S6: ATTACK — same sellerSig, buyerReceive redirected to attacker
const s6 = await post("/api/v1/settle", { ...terms, buyerReceive: attacker.address, sellerSig, validUntil });
show("S6 ATTACK same sig, buyerReceive -> attacker", s6);

// S7: ATTACK — same sellerSig, different buyer wallet
const s7 = await post("/api/v1/settle", { ...terms, buyer: attacker.address, sellerSig, validUntil });
show("S7 ATTACK same sig, buyer -> attacker", s7);

// S8: expired validUntil (1 hour in the past)
const s8 = await post("/api/v1/settle", {
  ...terms,
  sellerSig,
  validUntil: Math.floor(Date.now() / 1000) - 3600,
});
show("S8 ATTACK expired validUntil (-1h)", s8);

// S9: garbage signature
const s9 = await post("/api/v1/settle", {
  ...terms,
  sellerSig: "0x" + "11".repeat(65),
  validUntil,
});
show("S9 garbage sellerSig", s9);

// S10: signature from the WRONG wallet (buyer signs the consent message)
const wrongSig = await buyer.signMessage({ message });
const s10 = await post("/api/v1/settle", { ...terms, sellerSig: wrongSig, validUntil });
show("S10 buyer-signed consent passed as sellerSig", s10);

// S11: no sellerSig at all, consentOnly false
const s11 = await post("/api/v1/settle", { ...terms });
show("S11 no sellerSig, no consentOnly", s11);
