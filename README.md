# Bull ($BULL) — Proof of Concept

PoC for three Minor findings reported by Ryan Mahrez (GitHub: Ryanmahrez44)
to the Bull bug bounty program (https://bull.family/bounty).

## Findings

- **F-01** — Quorum with duplicate voters can never complete (payee never paid).
  `poc-contracts/test/Agreements.t.sol::test_quorum_duplicate_voters_lock`
- **F-02** — Late objection defeats the "unless" window (payer can renege and refund).
  `poc-contracts/test/Agreements.t.sol::test_late_objection_blocks_release`
- **C-1** — Webhook HMAC is unverifiable (no way to obtain or set the signing secret).
  Evidence scripts in `poc-sdk/` (`mcp-probe.mjs`, webhook validation W1–W4).

## Run the contract PoC (Foundry, local only, no mainnet funds)

```sh
cd poc-contracts
forge test
# expect: 25 passed, 0 failed
```

The tests etch the real deployed `BullAgreements` bytecode
(`0xef9cEeB6594504ADe1ec903A7A29a2BFe38EFC8B`, Robinhood Chain 4663) with only
the feeSigner constant replaced by `address(0)`; the findings' code paths do
not depend on the feeSigner. Solc 0.8.34, optimizer on, Cancun EVM.

## Run the webhook evidence (Node)

```sh
cd poc-sdk
npm install
node mcp-probe.mjs
```

This probes the public Bull API/MCP endpoints read-only; it does not touch
other users' data and moves no funds.
