// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuardTransient} from
    "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {TreasuryCoreStorage, MultiSigTransaction} from "./TreasuryCoreStorage.sol";
import {AccessModule} from "./modules/AccessModule.sol";
import {MultiSigModule} from "./modules/MultiSigModule.sol";
import {TimelockModule} from "./modules/TimelockModule.sol";
import {EmergencyModule} from "./modules/EmergencyModule.sol";
import {BudgetModule} from "./modules/BudgetModule.sol";
import {ITreasuryEvents} from "../interfaces/ITreasuryEvents.sol";
import {
    ZeroAddress,
    InvalidAmount,
    ModuleAlreadyRegistered,
    ModuleNotRegistered,
    ModuleCallFailed,
    NotAuthorized,
    RecoveryAddressNotSet,
    RecoveryTimelockNotExpired
} from "../interfaces/ITreasuryErrors.sol";
import {
    DEFAULT_ADMIN_ROLE,
    MODULE_YIELD,
    MODULE_STREAMING,
    RECOVERY_ROLE,
    TREASURY_CONTROLLER_ROLE
} from "../libraries/TreasuryConstants.sol";

contract TreasuryCore is
    EIP712Upgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    AccessModule,
    MultiSigModule,
    TimelockModule,
    EmergencyModule,
    BudgetModule
{
    using SafeERC20 for IERC20;
    using Address for address;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address[] calldata initialSigners,
        uint256 globalThreshold,
        uint256 defaultMinDelay
    ) external initializer {
        __AccessModule_init(admin, initialSigners, globalThreshold);
        __EIP712_init("TreasuryCore", "1");

        TreasuryCoreStorage.layout().defaultMinDelay = defaultMinDelay;
    }

    // ---- UUPS Upgrade Authorization ----

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ---- Virtual function overrides for cross-module access ----

    function _hasRole(bytes32 role, address account)
        internal
        view
        override(MultiSigModule, TimelockModule, EmergencyModule, BudgetModule)
        returns (bool)
    {
        return hasRole(role, account);
    }

    function _getActiveSignerCount() internal view override(MultiSigModule) returns (uint256) {
        return getActiveSignerCount();
    }

    function _hashTypedDataV4(bytes32 structHash)
        internal
        view
        override(MultiSigModule, EIP712Upgradeable)
        returns (bytes32)
    {
        return EIP712Upgradeable._hashTypedDataV4(structHash);
    }

    // ---- Asset Custody ----

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function transferETH(address payable to, uint256 amount)
        external
        whenNotPaused
        whenNotShutdown
        nonReentrant
        onlyModule(MODULE_STREAMING)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        Address.sendValue(to, amount);
        emit FundsTransferred(address(0), to, amount);
    }

    function transferERC20(address token, address to, uint256 amount)
        external
        whenNotPaused
        whenNotShutdown
        nonReentrant
        onlyModule(MODULE_STREAMING)
    {
        if (to == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        IERC20(token).safeTransfer(to, amount);
        emit FundsTransferred(token, to, amount);
    }

    /// Direct token transfer by yield module
    function transferERC20ForYield(address token, address to, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyModule(MODULE_YIELD)
    {
        if (to == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        IERC20(token).safeTransfer(to, amount);
        emit FundsTransferred(token, to, amount);
    }

    function approveERC20(address token, address spender, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyModule(MODULE_YIELD)
    {
        IERC20(token).safeIncreaseAllowance(spender, amount);
    }

    // ---- Module Registry ----

    function registerModule(bytes32 moduleName, address moduleAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if ($.moduleRegistry[moduleName] != address(0)) revert ModuleAlreadyRegistered(moduleName);
        if (moduleAddress == address(0)) revert ZeroAddress();
        $.moduleRegistry[moduleName] = moduleAddress;
        emit ModuleRegistered(moduleName, moduleAddress);
    }

    function revokeModule(bytes32 moduleName) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if ($.moduleRegistry[moduleName] == address(0)) revert ModuleNotRegistered(moduleName);
        delete $.moduleRegistry[moduleName];
        emit ModuleRevoked(moduleName);
    }

    function getModuleAddress(bytes32 moduleName) external view returns (address) {
        return TreasuryCoreStorage.layout().moduleRegistry[moduleName];
    }

    // ---- Emergency functions ----

    /// Execute recovery transfer after timelock (Tier 3)
    function executeEmergencyRecovery(address token, address to, uint256 amount)
        external
        nonReentrant
        onlyRole(RECOVERY_ROLE)
    {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (!$.recoveryAddresses[to]) revert RecoveryAddressNotSet();
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp < $.emergencyUnlockTime) revert RecoveryTimelockNotExpired($.emergencyUnlockTime);

        if (token == address(0)) {
            Address.sendValue(payable(to), amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit EmergencyRecoveryExecuted(to, amount);
    }

    // ---- View functions ----

    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ---- Cross-module lifecycle hooks (budget integration) ----

    /// @notice Freezes budget funds during transaction proposal.
    function _beforeProposeHook(uint256 txId, bytes32 budgetId, uint256 amount)
        internal
        override
    {
        _recordBudgetSpend(budgetId, txId, address(0), amount, address(0), "budget spend");
    }

    /// @notice Finalizes or releases budget funds after transaction execution.
    function _afterExecution(uint256 txId, bool success) internal override {
        MultiSigTransaction storage tx_ = TreasuryCoreStorage.layout().transactions[txId];
        if (tx_.budgetId == bytes32(0) || tx_.budgetAmount == 0) return;
        if (success) {
            finalizeBudgetSpend(tx_.budgetId, tx_.budgetAmount);
        } else {
            releaseBudgetFrozen(tx_.budgetId, tx_.budgetAmount);
        }
    }

    /// @notice Releases frozen budget funds on transaction cancellation.
    function _afterCancellation(uint256 txId) internal override {
        MultiSigTransaction storage tx_ = TreasuryCoreStorage.layout().transactions[txId];
        if (tx_.budgetId == bytes32(0) || tx_.budgetAmount == 0) return;
        releaseBudgetFrozen(tx_.budgetId, tx_.budgetAmount);
    }
}
