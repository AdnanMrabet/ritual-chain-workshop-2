# CipherBook contracts

Hardhat 3 workspace for the CipherBook commit–reveal prediction market.

```bash
corepack pnpm install
corepack pnpm exec hardhat build
corepack pnpm exec tsc --noEmit
corepack pnpm exec hardhat test solidity
```

The suite installs doubles at Ritual's canonical Scheduler, RitualWallet, registry, HTTP, and jq addresses. This verifies the full lifecycle without a live chain or wallet.

Deployment requires `DEPLOYER_PRIVATE_KEY`; do not commit it. See `.env.example` and the scripts directory.
