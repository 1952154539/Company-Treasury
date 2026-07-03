# ADR-003: Hub-and-Spoke over Monolithic Treasury

## Status
Accepted

## Context
The treasury system needs to manage assets, approve transactions, handle streaming payments, and integrate DeFi yield strategies. Two architectures were considered:

- **Monolithic**: All functionality in one contract
- **Hub-and-Spoke**: TreasuryCore as the central asset custodian with external specialized modules

## Decision
**Use Hub-and-Spoke: TreasuryCore holds all assets and delegates specialized operations to StreamingManager and YieldManager via explicit module registry.**

## Architecture
```
TreasuryCore (Hub)
  ├── holds all ETH + ERC20 assets
  ├── manages signers, multi-sig, timelock, budgets, emergency controls
  ├── moduleRegistry: authorized external contracts
  └── onlyModule() modifier gates asset transfers

StreamingManager (Spoke)
  └── creates/cancels streams, computes vesting, triggers transfers via TreasuryCore

YieldManager (Spoke)
  └── manages strategies, deposits/withdraws/harvests via TreasuryCore
```

## Rationale

1. **Asset custody is explicit**: All funds flow through TreasuryCore. `transferETH` and `transferERC20` are gated by `onlyModule(MODULE_STREAMING)` or `onlyModule(MODULE_YIELD)`. Adding a new module requires explicit admin registration.

2. **Independent upgradeability**: StreamingManager and YieldManager can be upgraded independently. A yield strategy logic bug doesn't require upgrading the core treasury (which holds funds).

3. **Gas optimization**: Core multi-sig operations don't load streaming or yield storage. Each contract has its own ERC-7201 namespace.

4. **Separation of concerns**: The strategist role manages DeFi positions without access to multi-sig approval. The treasury controller manages signers without access to yield strategies.

5. **Pluggable modules**: New modules (e.g., PayrollManager, SwapModule) can be added as separate UUPS proxies registered in the module registry, without modifying TreasuryCore.

## Module Communication Flow
```
StreamingManager.withdrawFromStream()
  → TreasuryCore.transferETH(to, amount)  [onlyModule(MODULE_STREAMING)]
  → Funds sent to recipient

YieldManager.depositToStrategy()
  → TreasuryCore.transferERC20ForYield(token, to, amount)  [onlyModule(MODULE_YIELD)]
  → Funds sent to YieldManager for vault deposit
```

## Consequences
- **Pro**: Clean separation, independent upgrades, explicit auth
- **Pro**: New modules added without touching core contract
- **Con**: Cross-contract calls add gas (acceptable for infrequent governance/treasury ops)
- **Con**: Module registry is a trusted registry — admin must carefully vet registered modules
