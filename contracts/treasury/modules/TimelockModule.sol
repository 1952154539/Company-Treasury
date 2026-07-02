// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TreasuryCoreStorage} from "../TreasuryCoreStorage.sol";
import {ITreasuryEvents} from "../../interfaces/ITreasuryEvents.sol";
import {
    MinDelayCannotDecrease,
    DelayTooShort,
    NotAuthorized
} from "../../interfaces/ITreasuryErrors.sol";
import {
    TREASURY_CONTROLLER_ROLE,
    MIN_MIN_DELAY,
    MAX_MIN_DELAY
} from "../../libraries/TreasuryConstants.sol";

abstract contract TimelockModule is ITreasuryEvents {
    // ---- Timelock configuration ----

    function setDefaultMinDelay(uint256 newDelay) external {
        if (!_hasRole(TREASURY_CONTROLLER_ROLE, msg.sender)) revert NotAuthorized(msg.sender, TREASURY_CONTROLLER_ROLE);
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (newDelay < MIN_MIN_DELAY) revert DelayTooShort(newDelay, MIN_MIN_DELAY);
        if (newDelay > MAX_MIN_DELAY) revert DelayTooShort(newDelay, MAX_MIN_DELAY);
        // Ratchet: delay can only increase (except admin override, handled via UUPS)
        if (newDelay < $.defaultMinDelay) revert MinDelayCannotDecrease($.defaultMinDelay, newDelay);

        uint256 oldDelay = $.defaultMinDelay;
        $.defaultMinDelay = newDelay;
        emit DefaultMinDelayUpdated(oldDelay, newDelay);
    }

    function getDefaultMinDelay() external view returns (uint256) {
        return TreasuryCoreStorage.layout().defaultMinDelay;
    }

    function getTransactionTimelock(uint256 txId) external view returns (uint256 scheduledAt, uint256 executableAt) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        scheduledAt = $.transactions[txId].scheduledAt;
        executableAt = $.transactions[txId].executableAt;
    }

    function _hasRole(bytes32 role, address account) internal view virtual returns (bool);

    uint256[49] private __timelockModuleGap;
}
