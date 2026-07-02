// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {TreasuryCoreStorage, Signer} from "../TreasuryCoreStorage.sol";
import {ITreasuryEvents} from "../../interfaces/ITreasuryEvents.sol";
import {
    SignerAlreadyExists,
    SignerNotFound,
    SignerNotActive,
    CannotRemoveLastSigner,
    ThresholdTooHigh,
    ThresholdTooLow,
    ZeroAddress,
    NotAuthorized
} from "../../interfaces/ITreasuryErrors.sol";
import {
    DEFAULT_ADMIN_ROLE,
    SIGNER_ROLE,
    PROPOSER_ROLE,
    EXECUTOR_ROLE,
    CANCELLER_ROLE,
    STRATEGIST_ROLE,
    BUDGET_MANAGER_ROLE,
    RECOVERY_ROLE,
    TREASURY_CONTROLLER_ROLE,
    MAX_SIGNERS
} from "../../libraries/TreasuryConstants.sol";

abstract contract AccessModule is AccessControlEnumerableUpgradeable, ITreasuryEvents {
    modifier onlyModule(bytes32 moduleName) {
        if (TreasuryCoreStorage.layout().moduleRegistry[moduleName] != msg.sender) {
            revert NotAuthorized(msg.sender, DEFAULT_ADMIN_ROLE);
        }
        _;
    }

    modifier onlySigner(address account) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (!$.signers[account].active) revert SignerNotFound(account);
        _;
    }

    function __AccessModule_init(
        address admin,
        address[] calldata initialSigners,
        uint256 globalThreshold
    ) internal onlyInitializing {
        __AccessControlEnumerable_init();

        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // Grant admin all operational roles for initial setup
        _grantRole(TREASURY_CONTROLLER_ROLE, admin);
        _grantRole(PROPOSER_ROLE, admin);
        _grantRole(EXECUTOR_ROLE, admin);
        _grantRole(CANCELLER_ROLE, admin);

        uint256 count = initialSigners.length;
        if (count > MAX_SIGNERS) revert ThresholdTooHigh(count, MAX_SIGNERS);
        if (globalThreshold == 0 || globalThreshold > count) revert ThresholdTooHigh(globalThreshold, count);

        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        $.globalThreshold = globalThreshold;

        for (uint256 i = 0; i < count; i++) {
            address signerAddr = initialSigners[i];
            if (signerAddr == address(0)) revert ZeroAddress();
            if ($.signers[signerAddr].active) revert SignerAlreadyExists(signerAddr);
            $.signers[signerAddr] = Signer({account: signerAddr, weight: 1, active: true, joinedAt: block.timestamp});
            $.signerList.push(signerAddr);
            _grantRole(SIGNER_ROLE, signerAddr);
            emit SignerAdded(signerAddr, 1);
        }
    }

    // ---- Signer management ----

    function addSigner(address account) external onlyRole(TREASURY_CONTROLLER_ROLE) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (account == address(0)) revert ZeroAddress();
        if ($.signers[account].active) revert SignerAlreadyExists(account);
        if ($.signerList.length >= MAX_SIGNERS) revert ThresholdTooHigh($.signerList.length, MAX_SIGNERS);

        $.signers[account] = Signer({account: account, weight: 1, active: true, joinedAt: block.timestamp});
        $.signerList.push(account);
        _grantRole(SIGNER_ROLE, account);
        emit SignerAdded(account, 1);
    }

    function removeSigner(address account) external onlyRole(TREASURY_CONTROLLER_ROLE) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (!$.signers[account].active) revert SignerNotFound(account);
        if ($.signerList.length <= $.globalThreshold) revert CannotRemoveLastSigner();

        $.signers[account].active = false;
        _revokeRole(SIGNER_ROLE, account);

        // Remove from signerList by replacing with last element
        address[] storage list = $.signerList;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == account) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
        emit SignerRemoved(account);
    }

    function setGlobalThreshold(uint256 newThreshold) external onlyRole(TREASURY_CONTROLLER_ROLE) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        uint256 activeCount = getActiveSignerCount();
        if (newThreshold == 0 || newThreshold > activeCount) {
            revert ThresholdTooHigh(newThreshold, activeCount);
        }
        uint256 oldThreshold = $.globalThreshold;
        $.globalThreshold = newThreshold;
        emit GlobalThresholdUpdated(oldThreshold, newThreshold);
    }

    // ---- View functions ----

    function getSigner(address account) external view returns (Signer memory) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        if (!$.signers[account].active) revert SignerNotFound(account);
        return $.signers[account];
    }

    function getSignerList() external view returns (address[] memory) {
        return TreasuryCoreStorage.layout().signerList;
    }

    function getActiveSignerCount() public view returns (uint256 count) {
        TreasuryCoreStorage.Layout storage $ = TreasuryCoreStorage.layout();
        address[] storage list = $.signerList;
        for (uint256 i = 0; i < list.length; i++) {
            if ($.signers[list[i]].active) count++;
        }
    }

    function getGlobalThreshold() external view returns (uint256) {
        return TreasuryCoreStorage.layout().globalThreshold;
    }

    function isActiveSigner(address account) external view returns (bool) {
        return TreasuryCoreStorage.layout().signers[account].active;
    }

    // Gap for upgrade safety
    uint256[49] private __accessModuleGap;
}
