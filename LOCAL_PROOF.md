# Local proof log

## Environment

- Hardhat 3.13
- Solidity 0.8.28
- pnpm 9.15.5
- Local simulated EVM; no wallet and no live-chain deployment

## Verified commands

```text
corepack pnpm exec hardhat build
No contracts to compile (latest sources already compiled)

corepack pnpm exec tsc --noEmit
Completed without errors

corepack pnpm exec hardhat test solidity
8 passing

node web/build.mjs
CipherBook static build ready in dist/
```

## Behaviors covered

1. Three phase deadlines and Scheduler booking.
2. RitualWallet execution funding.
3. Commitment privacy and duplicate rejection.
4. Reveal phase, side, and salt validation.
5. Reclaiming an unrevealed position.
6. Two-sided resolution and proportional payout.
7. One-sided invalidation and refunds.
8. Three oracle failures becoming refundable.
9. Permissionless expiry after the retry window.

The suite has eight test functions; the first covers scheduling and funding together.

