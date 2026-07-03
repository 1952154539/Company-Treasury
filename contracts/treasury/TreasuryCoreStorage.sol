// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum TransactionStatus {
    Draft,
    Queued,
    Ready,
    Executed,
    Cancelled,
    Failed
}

enum BudgetStatus {
    Draft,
    Active,
    Paused,
    Closed,
    Cancelled
}

enum RiskLevel {
    Low,
    Medium,
    High
}

struct Signer {
    address account;
    uint256 weight;
    bool active;
    uint256 joinedAt;
}

struct MultiSigTransaction {
    uint256 id;
    address proposer;
    address target;
    uint256 value;
    bytes data;
    TransactionStatus status;
    uint256 approvalsRequired;
    uint256 approvalCount;
    uint256 scheduledAt;
    uint256 minDelay;
    uint256 executableAt;
    uint256 createdAt;
    string description;
    bytes32 salt;
    // bitmap: bit i represents approval from signer at signerList[i]
    uint256 approvalBitmap;
    // Budget integration: if this tx spends from a budget
    bytes32 budgetId;
    uint256 budgetAmount;
}

struct Budget {
    bytes32 id;
    string name;
    address owner;
    uint256 totalAllocated;
    uint256 totalSpent;
    uint256 totalFrozen;
    uint64 startTime;
    uint64 endTime;
    BudgetStatus status;
    uint256 maxSingleSpend;
    uint256 approvalThreshold;
    // Per-budget approvers (separate from global signers)
    address[] approvers;
}

struct SpendRecord {
    bytes32 budgetId;
    uint256 transactionId;
    address token;
    uint256 amount;
    address recipient;
    uint256 timestamp;
    string purpose;
}

struct YieldStrategy {
    bytes32 id;
    string name;
    address vault;
    address asset;
    bool active;
    uint256 allocationCap;
    uint256 totalDeposited;
    RiskLevel riskLevel;
    uint256 addedAt;
}

struct YieldPosition {
    bytes32 id;
    bytes32 strategyId;
    uint256 depositedAssets;
    uint256 vaultShares;
    uint256 accruedYield;
    uint256 lastHarvestTime;
    uint256 createdAt;
    bool active;
}

// ERC-7201 namespaced storage layout
// keccak256(abi.encode(uint256(keccak256("treasury.core.storage")) - 1)) & ~bytes32(uint256(0xff))
library TreasuryCoreStorage {
    bytes32 private constant STORAGE_SLOT =
        0x78b80d75e1e78a0e3b63f253e108249e7b250f3e2a1b471a5c631e75a2b40900;

    struct Layout {
        // Transaction tracking
        uint256 transactionCounter;
        mapping(uint256 => MultiSigTransaction) transactions;
        mapping(bytes32 => bool) executedTxHashes;

        // Signers
        mapping(address => Signer) signers;
        address[] signerList;
        uint256 globalThreshold;

        // Timelock
        uint256 defaultMinDelay;

        // Budgets
        mapping(bytes32 => Budget) budgets;
        mapping(bytes32 => SpendRecord[]) budgetSpendHistory;
        bytes32[] budgetIds;
        // Per-budget approver lookup: budgetApprovers[approver][budgetId] => isApprover
        mapping(address => mapping(bytes32 => bool)) budgetApprovers;

        // Yield strategies
        mapping(bytes32 => YieldStrategy) strategies;
        mapping(bytes32 => YieldPosition) positions;
        bytes32[] strategyIds;

        // Emergency
        bool paused;
        bool emergencyShutdown;
        mapping(address => bool) recoveryAddresses;
        uint256 emergencyUnlockTime;
        address pendingRecoveryToken;

        // Module registry (authorized external modules)
        mapping(bytes32 => address) moduleRegistry;

        // Storage gap for future upgrades
        uint256[43] __gap;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
