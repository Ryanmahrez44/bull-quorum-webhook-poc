// Verify the live receipt signature recovers to Bull's fee signer (as SDK receipt() does).
import { recoverMessageAddress } from "viem";
const res = await fetch("https://www.bull.family/api/v1/receipts/1?escrow=0xD15dD54191d403156F7e29B6bD7637cEcE63E627");
const j = await res.json();
const signer = await recoverMessageAddress({ message: j.message, signature: j.signature });
console.log("receipt signer:", signer);
console.log("expected FEE_SIGNER: 0x585770c10434fA6D434b6B27316354f9D1688bd0");
console.log("match:", signer.toLowerCase() === "0x585770c10434fa6d434b6b27316354f9d1688bd0");
// quoteExpiresAt check on a fresh /settle fee quote
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
const seller = privateKeyToAccount(generatePrivateKey());
const buyer = privateKeyToAccount(generatePrivateKey());
const terms = { buyer: buyer.address, seller: seller.address, sellToken: "0x30768B5482e5dd8a2487cE0BE61E01fA03Af37ff", sellAmount: "1000", payAsset: "eth", payAmount: "0.25" };
const c1 = await (await fetch("https://www.bull.family/api/v1/settle", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...terms, consentOnly: true }) })).json();
const sig = await seller.signMessage({ message: c1.message });
const c2 = await (await fetch("https://www.bull.family/api/v1/settle", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...terms, sellerSig: sig, validUntil: c1.validUntil }) })).json();
const now = Math.floor(Date.now() / 1000);
console.log("now:", now, "quoteExpiresAt:", c2.quoteExpiresAt, "delta_s:", c2.quoteExpiresAt - now, "feeBps:", c2.feeBps);
// decode the fee-quote timestamp word (w10) from the tx data
const data = c2.transaction.data;
const w10 = BigInt("0x" + data.slice(10 + 10 * 64, 10 + 11 * 64)).toString();
console.log("fee-struct timestamp word w10:", w10, "delta vs now:", Number(w10) - now);
