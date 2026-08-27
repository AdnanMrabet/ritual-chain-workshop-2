# CipherBook

CipherBook is a self-resolving, commit–reveal prediction market built from the official Ritual Chain Workshop 2 repository. A bettor first submits a stake plus a hash; YES/NO and the private salt remain hidden until the reveal window. Ritual Scheduler later wakes the contract, HTTP `0x0801` reads the oracle, and jq `0x0803` extracts the observed value.

This is a real GitHub fork with original contract, test, interface, and documentation commits—not a ZIP re-upload.

## What changed

- Replaced open bets with sealed `commitPosition` and verified `revealPosition` phases.
- Added permissionless recovery for positions that were never revealed.
- Invalidates one-sided revealed pools rather than awarding a guaranteed side.
- Retries oracle resolution three times; an oracle failure is never interpreted as NO.
- Keeps payouts and refunds pull-based, with permissionless expiry for abandoned markets.
- Added an original CipherBook interface that explains and demonstrates the flow locally.
- Added eight Solidity tests with mocked Ritual system contracts and precompiles.

## Lifecycle

```text
Commit hash + stake → Reveal side + salt → Ritual Scheduler
                    → HTTP 0x0801 → jq 0x0803 → payout or refund
```
The commitment is:

```solidity
keccak256(abi.encodePacked(marketId, bettor, isYes, salt))
```

Keep the salt private until reveal. If it is lost, the side cannot be revealed, but the original sealed stake can be reclaimed after the reveal window.

## Local proof

Requirements: Node.js, Corepack, and pnpm.

```bash
cd hardhat
corepack pnpm install
corepack pnpm exec hardhat build
corepack pnpm exec tsc --noEmit
corepack pnpm exec hardhat test solidity
```

Expected result: `8 passing`.

Build the static walkthrough:

```bash
cd web
npm run build
```

The output is written to `web/dist`. It is a local proof artifact only; this repository does not use GitHub Pages and does not claim a live deployment.

## Ritual integration

The contract uses the canonical addresses centralized in `hardhat/contracts/ritual/RitualChain.sol`: Scheduler, RitualWallet, TEE Service Registry, HTTP `0x0801`, and jq `0x0803`.

The callback is bounded to three attempts. HTTP errors, malformed responses, non-2xx statuses, jq failures, missing executors, and one-sided pools lead to retries or a refundable invalid state.

## Deployment status

No wallet private key was provided for account 4, so no Ritual Chain deployment was attempted. Contract address and transaction hash should be left blank in the Proof of Building form.

## Project map

```text
hardhat/contracts/RitualPredict.sol   Commit–reveal market
hardhat/contracts/CipherBook.t.sol    Eight local contract tests
hardhat/scripts/                      Deployment and status utilities
web/                                  Original local interface
PRODUCT.md                            Product truth and constraints
DESIGN.md                             Visual system
LOCAL_PROOF.md                        Reproducible evidence
```
