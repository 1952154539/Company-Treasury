# Security Design

## Trust Assumptions

| Actor | Trust Level | Powers |
|-------|-------------|--------|
| DEFAULT_ADMIN_ROLE | Maximum | Upgrade contracts, manage roles, force-set timelock |
| TREASURY_CONTROLLER_ROLE | High | Add/remove signers, set threshold, pause/unpause, trigger shutdown |
| SIGNER_ROLE | Medium | Approve/reject multi-sig transactions |
| STRATEGIST_ROLE | Medium | Register strategies, deposit/withdraw/harvest yield |
| RECOVERY_ROLE | Limited | Initiate emergency recovery (48h delay) |

## Attack Surface & Mitigations

| Attack Vector | Severity | Mitigation |
|---------------|----------|------------|
| **Reentrancy** | Critical | `ReentrancyGuardTransient` (EIP-1153, Cancun) on all asset-transferring functions, Checks-Effects-Interactions pattern |
| **Storage collision (upgrade)** | Critical | ERC-7201 namespaced storage + `_disableInitializers()` on implementation |
| **Unauthorized upgrade** | Critical | `_authorizeUpgrade` restricted to `DEFAULT_ADMIN_ROLE` |
| **Signature replay** | High | EIP-712 typed data + nonce + deadline on `approveBySignature` |
| **Timelock bypass** | High | Ratchet mechanism: `setDefaultMinDelay` can only increase (except admin `forceSetMinDelay`) |
| **Double-spend (budget)** | High | Frozen balance tracking: `recordBudgetSpend` freezes → `finalizeBudgetSpend` spends → `releaseBudgetFrozen` on cancel |
| **Signer removal below threshold** | Medium | `removeSigner` prevents dropping active count below global threshold |
| **Duplicate transaction** | Medium | `executedTxHashes` mapping prevents replay |
| **Unauthorized module** | Medium | `onlyModule` modifier checks `moduleRegistry`, only admin can register |
| **Front-running (approval)** | Low | EIP-712 signatures are off-chain, bitmap prevents double-approval |
| **block.timestamp manipulation** | Low | Used only for relative delays (hours/days), not for randomness or precise timing |

## Emergency System

Three-tier escalation:

1. **Tier 1 — Pause** (immediate)
   - `pause()` / `unpause()` by TREASURY_CONTROLLER_ROLE
   - Blocks: `proposeTransaction`, `recordBudgetSpend`, all external module transfers
   - Does NOT block: approvals (existing transactions can accumulate signatures)

2. **Tier 2 — Shutdown** (immediate)
   - `triggerEmergencyShutdown()` by TREASURY_CONTROLLER_ROLE
   - Also pauses the contract
   - Blocks: all Tier 1 + all token transfers
   - Enables: Recovery initiation

3. **Tier 3 — Recovery** (48h delay)
   - `initiateEmergencyRecovery()` by RECOVERY_ROLE → sets 48h unlock time
   - `executeEmergencyRecovery()` by RECOVERY_ROLE → transfers assets after delay
   - Recovery addresses must be pre-approved by TREASURY_CONTROLLER_ROLE

## Upgrade Process

1. Deploy new implementation contract
2. Verify storage layout compatibility (ERC-7201 ensures no collision)
3. `DEFAULT_ADMIN_ROLE` calls `upgradeToAndCall()` on the proxy
4. Monitor for unexpected behavior

## Audit Recommendations

Before mainnet deployment:
- Third-party audit (Trail of Bits / OpenZeppelin)
- Invariant fuzzing with Echidna/Medusa
- Formal verification of multi-sig and timelock logic
- Multi-sig operation drill on testnet
- Emergency recovery drill on testnet
