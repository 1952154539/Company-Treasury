# ADR-002: ERC-7201 Namespaced Storage

## Status
Accepted

## Context
Upgradeable contracts (UUPS) risk storage collisions when new versions add state variables. The traditional approach uses unstructured storage (e.g., `keccak256("storage.slot")`) or storage gaps. ERC-7201 standardizes this with a deterministic formula.

## Decision
**Use ERC-7201 namespaced storage for all contracts.**

## Formula
```
slot = keccak256(abi.encode(uint256(keccak256("namespace.id")) - 1)) & ~bytes32(uint256(0xff))
```

Example from TreasuryCoreStorage:
```solidity
// keccak256(abi.encode(uint256(keccak256("treasury.core.storage")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant STORAGE_SLOT =
    0x78b80d75e1e78a0e3b63f253e108249e7b250f3e2a1b471a5c631e75a2b40900;
```

## Rationale

1. **Standardized collision avoidance**: ERC-7201 provides a mathematically guaranteed unique slot per namespace. Different contracts using different namespace strings will never collide.

2. **Easier audit than Diamond Storage**: Diamond Storage requires careful coordination of struct layouts. ERC-7201 is self-documenting — the namespace string encodes the owner contract.

3. **Forward compatibility**: New state variables can be added to the Layout struct without worrying about slot offsets. The entire Layout lives at one deterministic slot.

4. **OZ v5 native support**: OpenZeppelin Contracts v5.6+ uses ERC-7201 internally, making our pattern consistent with the dependency's upgrade approach.

## Implementation
Each contract defines a storage library with:
- A `Layout` struct containing all state variables
- A `STORAGE_SLOT` constant computed via ERC-7201
- A `layout()` function returning `Layout storage` via inline assembly

```solidity
library TreasuryCoreStorage {
    bytes32 private constant STORAGE_SLOT = 0x78b8...0900;
    struct Layout { /* all state variables */ uint256[43] __gap; }
    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
    }
}
```

## Consequences
- **Pro**: Deterministic slot, no collision risk, standard-compliant
- **Pro**: New state variables added to Layout without slot math
- **Con**: Slightly more verbose than inline state variable declarations
- **Con**: Requires inline assembly for slot assignment (audited pattern)
