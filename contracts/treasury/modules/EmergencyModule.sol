// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TreasuryCoreStorage} from "../TreasuryCoreStorage.sol";
import {ITreasuryEvents} from "../../interfaces/ITreasuryEvents.sol";
import {
    ContractPaused,
    EmergencyShutdownActive,
    RecoveryTimelockNotExpired,
    RecoveryAddressNotSet,
    NotAuthorized,
    ZeroAddress
} from "../../interfaces/ITreasuryErrors.sol";
import {TREASURY_CONTROLLER_ROLE, RECOVERY_ROLE, MAX_RECOVERY_DELAY} from "../../libraries/TreasuryConstants.sol";

abstract contract EmergencyModule is ITreasuryEvents {
    modifier whenNotPaused() {
        if (TreasuryCoreStorage.layout().paused) revert ContractPaused();
        _;
    }

    modifier whenNotShutdown() {
        if (TreasuryCoreStorage.layout().emergencyShutdown) revert EmergencyShutdownActive();
        _;
    }

    modifier onlyController() {
        if (!_hasRole(TREASURY_CONTROLLER_ROLE, msg.sender)) revert NotAuthorized(msg.sender, TREASURY_CONTROLLER_ROLE);
        _;
    }

    modifier onlyRecovery() {
        if (!_hasRole(RECOVERY_ROLE, msg.sender)) revert NotAuthorized(msg.sender, RECOVERY_ROLE);
        _;
    }

    // ---- Tier 1: Pause ----

    function pause() external onlyController {
        TreasuryCoreStorage.layout().paused = true;
        emit EmergencyPaused(msg.sender);
    }

    function unpause() external onlyController {
        TreasuryCoreStorage.layout().paused = false;
        emit EmergencyUnpaused(msg.sender);
    }

    function isPaused() external view returns (bool) {
        return TreasuryCoreStorage.layout().paused;
    }

    // ---- Tier 2: Emergency Shutdown ----

    function triggerEmergencyShutdown() external onlyController {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        $.emergencyShutdown = true;
        $.paused = true;
        emit EmergencyShutdownTriggered(msg.sender, block.timestamp);
    }

    function isEmergencyShutdown() external view returns (bool) {
        return TreasuryCoreStorage.layout().emergencyShutdown;
    }

    // ---- Tier 3: Recovery Mode ----

    function setRecoveryAddress(address recoveryAddr, bool enabled) external onlyController {
        if (recoveryAddr == address(0)) revert ZeroAddress();
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        emit RecoveryAddressUpdated(
            recoveryAddr, recoveryAddr // last state is tracked off-chain
        );
        $.recoveryAddresses[recoveryAddr] = enabled;
    }

    function isRecoveryAddress(address addr) external view returns (bool) {
        return TreasuryCoreStorage.layout().recoveryAddresses[addr];
    }

    function initiateEmergencyRecovery(address to, address /*token*/, uint256 amount)
        external
        onlyRecovery
        whenNotShutdown
    {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (!$.recoveryAddresses[to]) revert RecoveryAddressNotSet();

        $.emergencyUnlockTime = block.timestamp + MAX_RECOVERY_DELAY;
        emit EmergencyRecoveryInitiated(to, $.emergencyUnlockTime, amount);
    }

    function getEmergencyUnlockTime() external view returns (uint256) {
        return TreasuryCoreStorage.layout().emergencyUnlockTime;
    }

    function _hasRole(bytes32 role, address account) internal view virtual returns (bool);

    uint256[47] private __emergencyModuleGap;
}
