// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TreasuryCoreStorage, MultiSigTransaction, TransactionStatus} from "../TreasuryCoreStorage.sol";
import {ITreasuryEvents} from "../../interfaces/ITreasuryEvents.sol";
import {
    TransactionAlreadyApproved,
    TransactionNotInDraftState,
    TransactionNotReady,
    TransactionAlreadyExecuted,
    TransactionCancelled,
    TransactionExecutionFailed,
    InvalidTransactionTarget,
    DuplicateTransaction,
    NotAuthorized,
    ZeroAddress,
    TimelockNotExpired,
    ThresholdNotMet,
    ContractPaused
} from "../../interfaces/ITreasuryErrors.sol";
import {
    SIGNER_ROLE,
    EXECUTOR_ROLE,
    CANCELLER_ROLE,
    DONE_TIMESTAMP,
    MAX_SIGNERS,
    DEFAULT_ADMIN_ROLE
} from "../../libraries/TreasuryConstants.sol";

abstract contract MultiSigModule is ITreasuryEvents {
    using ECDSA for bytes32;

    bytes32 private constant APPROVE_TYPEHASH =
        keccak256("ApproveTransaction(uint256 txId,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) private _nonces;

    // ---- Transaction lifecycle ----

    /// @notice Propose a multi-sig transaction. Optionally link to a budget for spend tracking.
    /// @param target Destination address for the call
    /// @param value ETH value to send
    /// @param data Calldata for the call
    /// @param minDelay Minimum timelock delay (0 = use default, override only if > default)
    /// @param approvalThreshold Number of approvals required (0 = use global threshold)
    /// @param description Human-readable description
    /// @param salt Unique salt to prevent duplicate transactions
    /// @param budgetId Optional budget to debit (bytes32(0) if not budget-related)
    /// @param budgetAmount Amount to debit from the budget
    function proposeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 minDelay,
        uint256 approvalThreshold,
        string calldata description,
        bytes32 salt,
        bytes32 budgetId,
        uint256 budgetAmount
    ) external returns (uint256 txId) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if ($.paused) revert ContractPaused();
        if (target == address(0)) revert ZeroAddress();

        bytes32 txHash = keccak256(abi.encode(target, value, data, description, salt, budgetId));
        if ($.executedTxHashes[txHash]) revert DuplicateTransaction(txHash);

        if (approvalThreshold == 0) {
            approvalThreshold = $.globalThreshold;
        }
        uint256 activeCount = _getActiveSignerCount();
        if (approvalThreshold > activeCount) {
            revert ThresholdNotMet(approvalThreshold, activeCount);
        }

        txId = ++$.transactionCounter;

        MultiSigTransaction storage tx_ = $.transactions[txId];
        tx_.id = txId;
        tx_.proposer = msg.sender;
        tx_.target = target;
        tx_.value = value;
        tx_.data = data;
        tx_.status = TransactionStatus.Draft;
        tx_.approvalsRequired = approvalThreshold;
        tx_.minDelay = minDelay > 0 ? minDelay : $.defaultMinDelay;
        tx_.createdAt = block.timestamp;
        tx_.description = description;
        tx_.salt = salt;
        tx_.budgetId = budgetId;
        tx_.budgetAmount = budgetAmount;

        // Freeze budget funds if this transaction is linked to a budget
        if (budgetId != bytes32(0) && budgetAmount > 0) {
            _beforeProposeHook(txId, budgetId, budgetAmount);
        }

        emit TransactionProposed(txId, msg.sender, target, value, data, tx_.minDelay, approvalThreshold, description);
    }

    function approveTransaction(uint256 txId) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];
        if (tx_.status != TransactionStatus.Draft) revert TransactionNotInDraftState(txId);

        address signer = msg.sender;
        _validateSigner(signer);

        uint256 signerIndex = _getSignerIndex(signer);
        uint256 bit = uint256(1) << signerIndex;
        if (tx_.approvalBitmap & bit != 0) revert TransactionAlreadyApproved(txId, signer);

        tx_.approvalBitmap |= bit;
        tx_.approvalCount++;
        emit TransactionApproved(txId, signer, tx_.approvalCount);

        _checkAndAdvanceStatus(txId, tx_);
    }

    function approveBySignature(uint256 txId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];
        if (tx_.status != TransactionStatus.Draft) revert TransactionNotInDraftState(txId);

        if (block.timestamp > deadline) revert(); // signature expired

        bytes32 structHash = keccak256(abi.encode(APPROVE_TYPEHASH, txId, _useNonce(msg.sender), deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(v, r, s);

        _validateSigner(recovered);

        uint256 signerIndex = _getSignerIndex(recovered);
        uint256 bit = uint256(1) << signerIndex;
        if (tx_.approvalBitmap & bit != 0) revert TransactionAlreadyApproved(txId, recovered);

        tx_.approvalBitmap |= bit;
        tx_.approvalCount++;
        emit TransactionApproved(txId, recovered, tx_.approvalCount);

        _checkAndAdvanceStatus(txId, tx_);
    }

    function rejectTransaction(uint256 txId) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];
        if (tx_.status != TransactionStatus.Draft) revert TransactionNotInDraftState(txId);

        address signer = msg.sender;
        _validateSigner(signer);

        uint256 signerIndex = _getSignerIndex(signer);
        uint256 bit = uint256(1) << signerIndex;
        if (tx_.approvalBitmap & bit == 0) return;

        tx_.approvalBitmap &= ~bit;
        tx_.approvalCount--;
        emit TransactionRejected(txId, signer);
    }

    // ---- Execution ----

    function executeTransaction(uint256 txId) external payable {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];

        // Accept Queued if timelock expired, auto-advance to Ready
        if (tx_.status == TransactionStatus.Queued && block.timestamp >= tx_.executableAt) {
            tx_.status = TransactionStatus.Ready;
        }
        if (tx_.status != TransactionStatus.Ready) revert TransactionNotReady(txId);
        if (block.timestamp < tx_.executableAt) revert TimelockNotExpired(tx_.executableAt, block.timestamp);
        if (!_hasRole(EXECUTOR_ROLE, msg.sender) && !_hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized(msg.sender, EXECUTOR_ROLE);
        }

        tx_.status = TransactionStatus.Executed;
        bytes32 txHash =
            keccak256(abi.encode(tx_.target, tx_.value, tx_.data, tx_.description, tx_.salt, tx_.budgetId));
        $.executedTxHashes[txHash] = true;

        (bool success, bytes memory result) = tx_.target.call{value: tx_.value}(tx_.data);

        if (!success) {
            tx_.status = TransactionStatus.Failed;
            _afterExecution(txId, false);
            emit TransactionExecuted(txId, msg.sender, false, result);
            revert TransactionExecutionFailed(txId, result);
        }

        _afterExecution(txId, true);
        emit TransactionExecuted(txId, msg.sender, true, result);
    }

    function cancelTransaction(uint256 txId) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];

        if (
            tx_.status != TransactionStatus.Draft && tx_.status != TransactionStatus.Queued
                && tx_.status != TransactionStatus.Ready
        ) revert TransactionNotInDraftState(txId);

        if (!_hasRole(CANCELLER_ROLE, msg.sender) && tx_.proposer != msg.sender) {
            revert NotAuthorized(msg.sender, CANCELLER_ROLE);
        }

        tx_.status = TransactionStatus.Cancelled;
        _afterCancellation(txId);
        emit TransactionCancelled(txId, msg.sender);
    }

    // ---- Internal helpers ----

    function _checkAndAdvanceStatus(uint256 txId, MultiSigTransaction storage tx_) internal {
        if (tx_.approvalCount < tx_.approvalsRequired) return;

        if (tx_.minDelay > 0) {
            tx_.status = TransactionStatus.Queued;
            tx_.scheduledAt = block.timestamp;
            tx_.executableAt = block.timestamp + tx_.minDelay;
            emit TransactionQueued(txId, tx_.executableAt);
        } else {
            tx_.status = TransactionStatus.Ready;
            tx_.executableAt = block.timestamp;
        }
    }

    function _validateSigner(address signer) internal view {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (!$.signers[signer].active) revert NotAuthorized(signer, SIGNER_ROLE);
    }

    function _getSignerIndex(address signer) internal view returns (uint256) {
        address[] storage list = TreasuryCoreStorage.layout().signerList;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == signer) return i;
        }
        revert NotAuthorized(signer, SIGNER_ROLE);
    }

    function _useNonce(address owner) internal returns (uint256) {
        unchecked {
            return _nonces[owner]++;
        }
    }

    // ---- View functions ----

    function getTransaction(uint256 txId) external view returns (MultiSigTransaction memory) {
        return TreasuryCoreStorage.layout().transactions[txId];
    }

    function getTransactionApprovals(uint256 txId) external view returns (bool[] memory) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];
        uint256 len = $.signerList.length;
        bool[] memory approvals = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            approvals[i] = (tx_.approvalBitmap & (uint256(1) << i)) != 0;
        }
        return approvals;
    }

    function isApproved(uint256 txId, address signer) external view returns (bool) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        MultiSigTransaction storage tx_ = $.transactions[txId];
        uint256 signerIndex = type(uint256).max;
        address[] storage list = $.signerList;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == signer) {
                signerIndex = i;
                break;
            }
        }
        if (signerIndex == type(uint256).max) return false;
        return (tx_.approvalBitmap & (uint256(1) << signerIndex)) != 0;
    }

    function getNonce(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    // Virtual functions bridged by TreasuryCore
    function _hasRole(bytes32 role, address account) internal view virtual returns (bool);
    function _getActiveSignerCount() internal view virtual returns (uint256);
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32);

    /// @notice Hook called during proposeTransaction to freeze budget funds.
    /// Override in TreasuryCore to call BudgetModule._recordBudgetSpend.
    function _beforeProposeHook(uint256 txId, bytes32 budgetId, uint256 amount) internal virtual {}

    /// @notice Hook called after transaction execution. Override in TreasuryCore to
    /// finalize or release budget funds.
    function _afterExecution(uint256 txId, bool success) internal virtual {}

    /// @notice Hook called after transaction cancellation. Override in TreasuryCore to
    /// release frozen budget funds.
    function _afterCancellation(uint256 txId) internal virtual {}

    uint256[48] private __multiSigModuleGap;
}
