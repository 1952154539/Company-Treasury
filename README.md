# Company Treasury

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org)
[![Foundry](https://img.shields.io/badge/Foundry-latest-orange)](https://book.getfoundry.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-51%2F51%20passed-brightgreen)]()
[![Next.js](https://img.shields.io/badge/Next.js-16-black)](https://nextjs.org)

Production-grade on-chain corporate treasury system. Modular Hub-and-Spoke architecture with multi-sig governance, timelock, streaming payments, DeFi yield management, and budget allocation — all guarded by a 3-tier emergency system.

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│                   TreasuryCore (Hub)              │
│  UUPS Proxy + ERC-7201 Storage                   │
│  ┌──────────┬──────────┬──────────┬───────────┐  │
│  │ MultiSig │ Timelock │  Budget  │ Emergency │  │
│  │  Module  │  Module  │  Module  │  Module   │  │
│  └──────────┴──────────┴──────────┴───────────┘  │
│  Holds all ETH & ERC20 assets                    │
│  moduleRegistry -> onlyModule() gate             │
└────────┬──────────────────────────────┬──────────┘
         │                              │
    ┌────▼──────────┐          ┌────────▼──────────┐
    │StreamingManager│          │   YieldManager    │
    │  Sablier-style │          │  ERC-4626 DeFi    │
    │  linear vesting│          │  strategy mgmt    │
    └───────────────┘          └───────────────────┘
```

## Features

| Domain | Features |
|--------|----------|
| **Multi-Sig** | N/M threshold, EIP-712 gasless signatures, bitmap approval tracking, proposal lifecycle |
| **Timelock** | Configurable delay, ratchet mechanism (increase-only), auto Queued->Ready |
| **Streaming** | Sablier-style linear vesting, cliff support, cancelable streams, batch creation |
| **Yield** | ERC-4626 vault integration, strategy whitelist + allocation cap, harvest/rebalance |
| **Budget** | Department allocation, frozen balance tracking, spend history, per-budget approvers |
| **Emergency** | 3-tier: Pause -> Shutdown -> Recovery (48h timelock) |
| **Access Control** | 9 granular roles via OpenZeppelin AccessControlEnumerable |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Smart Contracts | Solidity 0.8.24 + Foundry + OpenZeppelin v5.6 |
| Upgrade Pattern | UUPS + ERC-7201 namespaced storage |
| Reentrancy | ReentrancyGuardTransient (EIP-1153, Cancun) |
| Signatures | EIP-712 typed structured data |
| Frontend | Next.js 16 + TypeScript + Tailwind CSS |
| Web3 | Wagmi v2 + Viem + ConnectKit |
| CI/CD | GitHub Actions |
| Testing | Foundry (51 tests: unit + fuzz + invariant + integration + edge) |

## Quick Start

### Contracts

```bash
forge install
forge build
forge test -vvv        # 51 tests
forge test --gas-report
```

### Frontend

```bash
cd frontend
npm install --legacy-peer-deps
npm run dev             # http://localhost:3000
```

## Test Suite

51 tests across 6 categories:

| Category | Count | Coverage |
|----------|-------|----------|
| Unit (original) | 17 | Multi-sig, signers, timelock, budgets, streams, yield, emergency |
| Fuzz (streaming) | 5 x 1000 | Vesting math, cliff, withdrawals |
| Fuzz (multi-sig) | 4 x 1000 | Signer count, threshold, approval order, bitmap |
| Invariants | 7 | Budget accounting, cancellation, module auth, signer consistency |
| Integration | 7 | Full workflows: budget+tx, timelock, stream, pause, recovery, yield |
| Edge Cases | 10 | Threshold boundaries, zero values, bitmap collision, auth failures |

## Architecture Decisions

- [ADR-001: UUPS over Diamond](docs/ADR/001-uups-over-diamond.md)
- [ADR-002: ERC-7201 Namespaced Storage](docs/ADR/002-erc7201-storage.md)
- [ADR-003: Hub-and-Spoke over Monolithic](docs/ADR/003-hub-and-spoke.md)

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for threat model and emergency procedures.

- `ReentrancyGuardTransient` (EIP-1153) on all asset transfers
- ERC-7201 prevents upgrade storage collisions
- Ratchet timelock (decrease requires admin override)
- Budget frozen-fund tracking prevents double-spend
- 3-tier emergency: Pause -> Shutdown -> 48h Recovery

## Deployment

```bash
export PRIVATE_KEY=0x...
export TREASURY_ADMIN=0x...
export SIGNER_THRESHOLD=2
export MIN_DELAY=86400
export SIGNERS=0x...,0x...,0x...

make deploy-sepolia
```

## Resume Highlights

> **Company Treasury -- On-chain Corporate Treasury System**
>
> * Designed a modular Hub-and-Spoke treasury using UUPS upgradeable proxies with ERC-7201 namespaced storage, integrating N/M multi-sig (EIP-712 gasless approval + bitmap tracking), ratchet timelock, Sablier-style linear vesting streams, and ERC-4626 DeFi yield strategy management
> * Built 3-tier emergency system (Pause -> Shutdown -> 48h Recovery) with EIP-1153 transient storage reentrancy protection
> * Authored 51-test Foundry suite (fuzz/invariant/integration/edge); deployed and verified on testnet
> * Built Next.js 16 frontend with Wagmi/Viem for wallet interaction, real-time multi-sig approval tracking, and EIP-712 in-browser signature workflow

## License

MIT
