# ADR-001: UUPS Proxy over Diamond (EIP-2535)

## Status
Accepted

## Context
The treasury system requires upgradeable contracts. Two patterns were considered:

- **Diamond (EIP-2535)**: Multi-facet proxy with `delegatecall`-based function routing
- **UUPS (EIP-1822)**: Single-implementation proxy with upgrade logic in the implementation

## Decision
**Use UUPS proxies with independent proxy contracts for each module.**

## Rationale

1. **Security surface**: Diamond's `delegatecall`-based facet routing means every function call goes through the Diamond proxy, sharing storage across all facets. A storage collision in one facet can corrupt the entire system. UUPS isolates each contract's storage.

2. **Storage management complexity**: Diamond requires careful namespace management (Diamond Storage / AppStorage pattern) to prevent facet storage collisions. With 5 sub-modules (MultiSig, Timelock, Budget, Emergency, Access) plus 2 external modules (Streaming, Yield), storage coordination becomes error-prone.

3. **Hub-and-Spoke architecture**: TreasuryCore holds all assets and delegates to external modules (StreamingManager, YieldManager) via explicit module registry + `onlyModule` modifier. This is more auditable than Diamond's implicit facet routing.

4. **Independent upgrade cadence**: StreamingManager and YieldManager can be upgraded independently without touching TreasuryCore's storage. Diamond would require coordinating all facet upgrades through a single diamondCut.

5. **ERC-7201 namespaced storage**: Each contract uses ERC-7201 formula for storage slot derivation, eliminating collision risk during upgrades without the complexity of Diamond storage.

## Consequences

- **Pro**: Clear module boundaries, simpler audit, independent upgrade paths
- **Pro**: TreasuryCore asset custody is explicit and auditable
- **Con**: Three separate proxy contracts to manage (but TreasuryFactory handles deployment)
- **Con**: Cross-contract calls have gas overhead (acceptable for governance operations)
