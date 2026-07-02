// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasuryEvents {
    // Multi-sig
    event TransactionProposed(
        uint256 indexed txId,
        address indexed proposer,
        address target,
        uint256 value,
        bytes data,
        uint256 minDelay,
        uint256 approvalThreshold,
        string description
    );
    event TransactionApproved(uint256 indexed txId, address indexed signer, uint256 approvalCount);
    event TransactionRejected(uint256 indexed txId, address indexed signer);
    event TransactionQueued(uint256 indexed txId, uint256 executableAt);
    event TransactionExecuted(uint256 indexed txId, address executor, bool success, bytes result);
    event TransactionCancelled(uint256 indexed txId, address canceller);

    // Signer management
    event SignerAdded(address indexed signer, uint256 weight);
    event SignerRemoved(address indexed signer);
    event GlobalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event DefaultMinDelayUpdated(uint256 oldDelay, uint256 newDelay);

    // Streaming
    event StreamCreated(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint64 startTime,
        uint64 endTime,
        uint64 cliffDuration,
        bool cancelable
    );
    event StreamWithdrawn(uint256 indexed streamId, address indexed recipient, uint256 amount);
    event StreamCancelled(uint256 indexed streamId, uint256 remainingBalance, address refundedTo);

    // Yield
    event StrategyAdded(
        bytes32 indexed strategyId,
        string name,
        address vault,
        address asset,
        uint256 allocationCap
    );
    event StrategyRemoved(bytes32 indexed strategyId);
    event StrategyUpdated(bytes32 indexed strategyId, uint256 newAllocationCap);
    event YieldDeposited(bytes32 indexed strategyId, uint256 amount, uint256 shares, bytes32 positionId);
    event YieldWithdrawn(bytes32 indexed strategyId, uint256 assets, uint256 shares);
    event YieldHarvested(bytes32 indexed strategyId, uint256 amount);
    event YieldRebalanced(bytes32 indexed fromStrategy, bytes32 indexed toStrategy, uint256 amount);

    // Budget
    event BudgetCreated(
        bytes32 indexed budgetId,
        string name,
        address indexed owner,
        uint256 totalAllocated,
        uint64 startTime,
        uint64 endTime,
        address[] approvers,
        uint256 approvalThreshold
    );
    event BudgetSpent(
        bytes32 indexed budgetId,
        uint256 indexed txId,
        address token,
        uint256 amount,
        address recipient,
        string purpose
    );
    event BudgetModified(bytes32 indexed budgetId, uint256 newAllocation, uint64 newEndTime);
    event BudgetClosed(bytes32 indexed budgetId, uint256 unspentAmount);
    event BudgetActivated(bytes32 indexed budgetId);

    // Emergency
    event EmergencyPaused(address indexed triggeredBy);
    event EmergencyUnpaused(address indexed triggeredBy);
    event EmergencyShutdownTriggered(address indexed triggeredBy, uint256 timestamp);
    event EmergencyRecoveryInitiated(address indexed to, uint256 unlockTime, uint256 amount);
    event EmergencyRecoveryExecuted(address indexed to, uint256 amount);
    event RecoveryAddressUpdated(address indexed oldAddress, address indexed newAddress);

    // Module
    event ModuleRegistered(bytes32 indexed moduleName, address indexed moduleAddress);
    event ModuleRevoked(bytes32 indexed moduleName);

    // Treasury core
    event ETHReceived(address indexed sender, uint256 amount);
    event ERC20Received(address indexed token, address indexed sender, uint256 amount);
    event FundsTransferred(address indexed token, address indexed to, uint256 amount);
}
