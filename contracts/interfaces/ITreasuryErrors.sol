// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Access control
error NotAuthorized(address caller, bytes32 role);
error SignerAlreadyExists(address signer);
error SignerNotFound(address signer);
error SignerNotActive(address signer);
error CannotRemoveLastSigner();
error ThresholdTooHigh(uint256 threshold, uint256 totalSigners);
error ThresholdTooLow(uint256 threshold);
error ThresholdNotMet(uint256 required, uint256 actual);

// Multi-sig
error TransactionAlreadyApproved(uint256 txId, address signer);
error TransactionNotInDraftState(uint256 txId);
error TransactionNotReady(uint256 txId);
error TransactionAlreadyExecuted(uint256 txId);
error TransactionExecutionFailed(uint256 txId, bytes reason);
error TransactionCancelled(uint256 txId);
error InvalidTransactionTarget(address target);
error DuplicateTransaction(bytes32 txHash);

// Timelock
error TimelockNotExpired(uint256 executableAt, uint256 currentTime);
error MinDelayCannotDecrease(uint256 currentDelay, uint256 newDelay);
error DelayTooShort(uint256 delay, uint256 minDelay);
error OperationAlreadyScheduled(bytes32 operationId);

// Budget
error BudgetNotFound(bytes32 budgetId);
error BudgetNotActive(bytes32 budgetId);
error BudgetExceeded(bytes32 budgetId, uint256 requested, uint256 available);
error BudgetExpired(bytes32 budgetId, uint256 endTime);
error BudgetNotStarted(bytes32 budgetId, uint256 startTime);
error MaxSingleSpendExceeded(uint256 amount, uint256 maxAmount);
error BudgetHasPendingTransactions(bytes32 budgetId);

// Streaming
error StreamNotFound(uint256 streamId);
error StreamNotActive(uint256 streamId);
error StreamNotCancelable(uint256 streamId);
error StreamCliffNotReached(uint256 streamId, uint256 cliffTime, uint256 currentTime);
error StreamNotStarted(uint256 streamId);
error NoReleasableAmount(uint256 streamId);
error InvalidStreamDuration(uint256 startTime, uint256 endTime);
error StreamAmountZero();

// Yield
error StrategyNotFound(bytes32 strategyId);
error StrategyNotActive(bytes32 strategyId);
error StrategyCapExceeded(bytes32 strategyId, uint256 requested, uint256 cap);
error VaultNotERC4626(address vault);
error InsufficientShares(uint256 received, uint256 minExpected);
error InsufficientAssets(uint256 received, uint256 minExpected);
error PositionNotActive(bytes32 positionId);

// Emergency
error ContractPaused();
error EmergencyShutdownActive();
error RecoveryTimelockNotExpired(uint256 unlockTime);
error RecoveryAddressNotSet();
error NotInEmergencyMode();

// Module
error ModuleAlreadyRegistered(bytes32 moduleName);
error ModuleNotRegistered(bytes32 moduleName);
error ModuleCallFailed(bytes reason);

// General
error ZeroAddress();
error InvalidAmount();
error ArrayLengthMismatch();
