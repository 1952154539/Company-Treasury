// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TreasuryCoreStorage, Budget, BudgetStatus, SpendRecord} from "../TreasuryCoreStorage.sol";
import {ITreasuryEvents} from "../../interfaces/ITreasuryEvents.sol";
import {
    BudgetNotFound,
    BudgetNotActive,
    BudgetExceeded,
    BudgetExpired,
    BudgetNotStarted,
    MaxSingleSpendExceeded,
    BudgetHasPendingTransactions,
    ZeroAddress,
    InvalidAmount,
    NotAuthorized
} from "../../interfaces/ITreasuryErrors.sol";
import {BUDGET_MANAGER_ROLE, DEFAULT_ADMIN_ROLE} from "../../libraries/TreasuryConstants.sol";

abstract contract BudgetModule is ITreasuryEvents {
    // ---- Budget CRUD ----

    function createBudget(
        string calldata name,
        address owner,
        uint256 totalAllocated,
        uint64 startTime,
        uint64 endTime,
        address[] calldata approvers,
        uint256 approvalThreshold,
        uint256 maxSingleSpend
    ) external returns (bytes32 budgetId) {
        if (!_hasRole(BUDGET_MANAGER_ROLE, msg.sender) && !_hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized(msg.sender, BUDGET_MANAGER_ROLE);
        }
        if (owner == address(0)) revert ZeroAddress();
        if (totalAllocated == 0) revert InvalidAmount();

        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        budgetId = keccak256(abi.encodePacked(name, owner, block.timestamp, msg.sender));

        $.budgets[budgetId] = Budget({
            id: budgetId,
            name: name,
            owner: owner,
            totalAllocated: totalAllocated,
            totalSpent: 0,
            totalFrozen: 0,
            startTime: startTime,
            endTime: endTime,
            status: BudgetStatus.Active,
            maxSingleSpend: maxSingleSpend,
            approvalThreshold: approvalThreshold > 0 ? approvalThreshold : $.globalThreshold
        });
        $.budgetIds.push(budgetId);

        emit BudgetCreated(
            budgetId,
            name,
            owner,
            totalAllocated,
            startTime,
            endTime,
            approvers,
            approvalThreshold
        );
    }

    function activateBudget(bytes32 budgetId) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        if (budget.owner == address(0)) revert BudgetNotFound(budgetId);
        if (!_hasRole(BUDGET_MANAGER_ROLE, msg.sender) && budget.owner != msg.sender) {
            revert NotAuthorized(msg.sender, BUDGET_MANAGER_ROLE);
        }
        budget.status = BudgetStatus.Active;
        emit BudgetActivated(budgetId);
    }

    function modifyBudget(bytes32 budgetId, uint256 newAllocation, uint64 newEndTime) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        if (budget.owner == address(0)) revert BudgetNotFound(budgetId);
        if (!_hasRole(BUDGET_MANAGER_ROLE, msg.sender) && budget.owner != msg.sender) {
            revert NotAuthorized(msg.sender, BUDGET_MANAGER_ROLE);
        }

        if (newAllocation > 0) {
            budget.totalAllocated = newAllocation;
        }
        if (newEndTime > 0) {
            budget.endTime = newEndTime;
        }
        emit BudgetModified(budgetId, newAllocation, newEndTime);
    }

    function closeBudget(bytes32 budgetId) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        if (budget.owner == address(0)) revert BudgetNotFound(budgetId);
        if (!_hasRole(BUDGET_MANAGER_ROLE, msg.sender) && budget.owner != msg.sender) {
            revert NotAuthorized(msg.sender, BUDGET_MANAGER_ROLE);
        }
        if (budget.totalFrozen > 0) revert BudgetHasPendingTransactions(budgetId);

        budget.status = BudgetStatus.Closed;
        uint256 unspent = budget.totalAllocated - budget.totalSpent;
        emit BudgetClosed(budgetId, unspent);
    }

    // ---- Budget Spend Tracking ----

    /// Called internally by MultiSigModule after successful execution
    function recordBudgetSpend(
        bytes32 budgetId,
        uint256 txId,
        address token,
        uint256 amount,
        address recipient,
        string calldata purpose
    ) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        if (budget.owner == address(0)) revert BudgetNotFound(budgetId);
        if (budget.status != BudgetStatus.Active) revert BudgetNotActive(budgetId);
        if (block.timestamp < budget.startTime) revert BudgetNotStarted(budgetId, budget.startTime);
        if (block.timestamp > budget.endTime) revert BudgetExpired(budgetId, budget.endTime);

        uint256 available = budget.totalAllocated - budget.totalSpent - budget.totalFrozen;
        if (amount > available) revert BudgetExceeded(budgetId, amount, available);
        if (budget.maxSingleSpend > 0 && amount > budget.maxSingleSpend) {
            revert MaxSingleSpendExceeded(amount, budget.maxSingleSpend);
        }

        budget.totalFrozen += amount;

        $.budgetSpendHistory[budgetId].push(
            SpendRecord({
                budgetId: budgetId,
                transactionId: txId,
                token: token,
                amount: amount,
                recipient: recipient,
                timestamp: block.timestamp,
                purpose: purpose
            })
        );

        emit BudgetSpent(budgetId, txId, token, amount, recipient, purpose);
    }

    /// Called by MultiSigModule after execution completes
    function finalizeBudgetSpend(bytes32 budgetId, uint256 amount) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        budget.totalFrozen -= amount;
        budget.totalSpent += amount;
    }

    /// Called by MultiSigModule when a transaction is cancelled to release frozen funds
    function releaseBudgetFrozen(bytes32 budgetId, uint256 amount) external {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        if (budget.totalFrozen >= amount) {
            budget.totalFrozen -= amount;
        } else {
            budget.totalFrozen = 0;
        }
    }

    // ---- View functions ----

    function getBudget(bytes32 budgetId) external view returns (Budget memory) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if ($.budgets[budgetId].owner == address(0)) revert BudgetNotFound(budgetId);
        return $.budgets[budgetId];
    }

    function getBudgetAvailable(bytes32 budgetId) external view returns (uint256) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        Budget storage budget = $.budgets[budgetId];
        if (budget.owner == address(0)) revert BudgetNotFound(budgetId);
        return budget.totalAllocated - budget.totalSpent - budget.totalFrozen;
    }

    function getBudgetSpendHistory(bytes32 budgetId) external view returns (SpendRecord[] memory) {
        return TreasuryCoreStorage.layout().budgetSpendHistory[budgetId];
    }

    function getBudgetIds() external view returns (bytes32[] memory) {
        return TreasuryCoreStorage.layout().budgetIds;
    }

    function _hasRole(bytes32 role, address account) internal view virtual returns (bool);

    uint256[47] private __budgetModuleGap;
}
