// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ReentrancyGuardTransient} from
    "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ITreasuryEvents} from "../interfaces/ITreasuryEvents.sol";
import {
    StrategyNotFound,
    StrategyNotActive,
    StrategyCapExceeded,
    VaultNotERC4626,
    InsufficientShares,
    InsufficientAssets,
    PositionNotActive,
    ZeroAddress,
    InvalidAmount,
    NotAuthorized,
    ContractPaused
} from "../interfaces/ITreasuryErrors.sol";
import {
    DEFAULT_ADMIN_ROLE,
    STRATEGIST_ROLE,
    TREASURY_CONTROLLER_ROLE,
    MODULE_YIELD,
    MAX_BPS
} from "../libraries/TreasuryConstants.sol";

struct StrategyData {
    bytes32 id;
    string name;
    address vault;
    address asset;
    bool active;
    uint256 allocationCap;
    uint256 totalDeposited;
    uint8 riskLevel;
    uint256 addedAt;
}

struct PositionData {
    bytes32 id;
    bytes32 strategyId;
    uint256 depositedAssets;
    uint256 vaultShares;
    uint256 accruedYield;
    uint256 lastHarvestTime;
    uint256 createdAt;
    bool active;
}

// ERC-7201 storage
// keccak256(abi.encode(uint256(keccak256("treasury.yield.storage")) - 1)) & ~bytes32(uint256(0xff))
library YieldStorage {
    bytes32 private constant STORAGE_SLOT =
        0x8b7b7d7e7b8e3e0d5a3c1e9e7a5b3d1f7e9c7b5a3d1f5e9a7b3d1f5e7a9b3d00;

    struct Layout {
        mapping(bytes32 => StrategyData) strategies;
        mapping(bytes32 => PositionData) positions;
        bytes32[] strategyIds;
        address treasuryCore;
        bool paused;
        uint256[46] __gap;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

interface ITreasuryYield {
    function transferERC20ForYield(address token, address to, uint256 amount) external;
    function approveERC20(address token, address spender, uint256 amount) external;
}

contract YieldManager is
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardTransient,
    ITreasuryEvents
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant POSITION_NAMESPACE = keccak256("YIELD_POSITION");

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address treasury) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STRATEGIST_ROLE, admin);
        _grantRole(TREASURY_CONTROLLER_ROLE, admin);

        if (treasury == address(0)) revert ZeroAddress();
        YieldStorage.layout().treasuryCore = treasury;
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ---- Strategy Management ----

    function addStrategy(
        string calldata name,
        address vault,
        address asset,
        uint256 allocationCap,
        uint8 riskLevel
    ) external onlyRole(STRATEGIST_ROLE) returns (bytes32 strategyId) {
        if (vault == address(0) || asset == address(0)) revert ZeroAddress();

        // Verify vault supports ERC-4626
        try IERC4626(vault).asset() returns (address vaultAsset) {
            if (vaultAsset != asset) revert VaultNotERC4626(vault);
        } catch {
            revert VaultNotERC4626(vault);
        }

        strategyId = keccak256(abi.encodePacked(name, vault, block.timestamp));

        YieldStorage.Layout storage $ = YieldStorage.layout();
        $.strategies[strategyId] = StrategyData({
            id: strategyId,
            name: name,
            vault: vault,
            asset: asset,
            active: true,
            allocationCap: allocationCap,
            totalDeposited: 0,
            riskLevel: riskLevel,
            addedAt: block.timestamp
        });
        $.strategyIds.push(strategyId);

        emit StrategyAdded(strategyId, name, vault, asset, allocationCap);
    }

    function removeStrategy(bytes32 strategyId) external onlyRole(STRATEGIST_ROLE) {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        if (!$.strategies[strategyId].active) revert StrategyNotActive(strategyId);
        $.strategies[strategyId].active = false;
        emit StrategyRemoved(strategyId);
    }

    function updateStrategyCap(bytes32 strategyId, uint256 newCap)
        external
        onlyRole(STRATEGIST_ROLE)
    {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        if (!$.strategies[strategyId].active) revert StrategyNotActive(strategyId);
        $.strategies[strategyId].allocationCap = newCap;
        emit StrategyUpdated(strategyId, newCap);
    }

    // ---- Position Management ----

    function depositToStrategy(bytes32 strategyId, uint256 amount, uint256 minSharesOut)
        external
        onlyRole(STRATEGIST_ROLE)
        nonReentrant
        returns (bytes32 positionId, uint256 shares)
    {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        if ($.paused) revert ContractPaused();
        StrategyData storage strategy = $.strategies[strategyId];
        if (!strategy.active) revert StrategyNotActive(strategyId);
        if (amount == 0) revert InvalidAmount();

        // Check allocation cap
        if (strategy.totalDeposited + amount > strategy.allocationCap) {
            revert StrategyCapExceeded(strategyId, strategy.totalDeposited + amount, strategy.allocationCap);
        }

        // Get assets from TreasuryCore
        ITreasuryYield($.treasuryCore).transferERC20ForYield(strategy.asset, address(this), amount);

        // Deposit to vault
        IERC20(strategy.asset).safeIncreaseAllowance(strategy.vault, amount);
        shares = IERC4626(strategy.vault).deposit(amount, address($.treasuryCore));
        if (shares < minSharesOut) revert InsufficientShares(shares, minSharesOut);

        strategy.totalDeposited += amount;

        positionId = keccak256(abi.encodePacked(POSITION_NAMESPACE, strategyId, block.timestamp, amount));
        $.positions[positionId] = PositionData({
            id: positionId,
            strategyId: strategyId,
            depositedAssets: amount,
            vaultShares: shares,
            accruedYield: 0,
            lastHarvestTime: block.timestamp,
            createdAt: block.timestamp,
            active: true
        });

        emit YieldDeposited(strategyId, amount, shares, positionId);
    }

    function withdrawFromStrategy(bytes32 positionId, uint256 shares, uint256 minAssetsOut)
        external
        onlyRole(STRATEGIST_ROLE)
        nonReentrant
        returns (uint256 assets)
    {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        PositionData storage pos = $.positions[positionId];
        if (!pos.active) revert PositionNotActive(positionId);

        StrategyData storage strategy = $.strategies[pos.strategyId];
        if (!strategy.active) revert StrategyNotActive(pos.strategyId);

        // Need to transfer shares from TreasuryCore to here first
        ITreasuryYield($.treasuryCore).transferERC20ForYield(strategy.vault, address(this), shares);
        IERC20(strategy.vault).safeIncreaseAllowance(strategy.vault, shares);

        assets = IERC4626(strategy.vault).redeem(shares, $.treasuryCore, address(this));
        if (assets < minAssetsOut) revert InsufficientAssets(assets, minAssetsOut);

        strategy.totalDeposited = strategy.totalDeposited > assets
            ? strategy.totalDeposited - assets
            : 0;

        pos.active = false;
        emit YieldWithdrawn(pos.strategyId, assets, shares);
    }

    function harvestYield(bytes32 strategyId)
        external
        onlyRole(STRATEGIST_ROLE)
        nonReentrant
        returns (uint256 harvestedAmount)
    {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        StrategyData storage strategy = $.strategies[strategyId];
        if (!strategy.active) revert StrategyNotActive(strategyId);

        uint256 currentShares = IERC20(strategy.vault).balanceOf($.treasuryCore);
        uint256 currentAssets = IERC4626(strategy.vault).convertToAssets(currentShares);
        uint256 principal = strategy.totalDeposited;

        if (currentAssets > principal) {
            harvestedAmount = currentAssets - principal;
            // Withdraw yield only
            uint256 yieldShares =
                IERC4626(strategy.vault).convertToShares(harvestedAmount);
            if (yieldShares > 0) {
                ITreasuryYield($.treasuryCore).transferERC20ForYield(
                    strategy.vault, address(this), yieldShares
                );
                IERC20(strategy.vault).safeIncreaseAllowance(strategy.vault, yieldShares);
                IERC4626(strategy.vault).redeem(yieldShares, $.treasuryCore, address(this));
            }
        }

        emit YieldHarvested(strategyId, harvestedAmount);
    }

    function rebalance(
        bytes32 fromStrategyId,
        bytes32 toStrategyId,
        uint256 shares,
        uint256 minAssetsOut
    ) external onlyRole(STRATEGIST_ROLE) nonReentrant {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        if (!$.strategies[fromStrategyId].active) revert StrategyNotActive(fromStrategyId);
        if (!$.strategies[toStrategyId].active) revert StrategyNotActive(toStrategyId);

        address fromVault = $.strategies[fromStrategyId].vault;
        ITreasuryYield($.treasuryCore).transferERC20ForYield(fromVault, address(this), shares);
        IERC20(fromVault).safeIncreaseAllowance(fromVault, shares);
        uint256 assets = IERC4626(fromVault).redeem(shares, address(this), address(this));
        if (assets < minAssetsOut) revert InsufficientAssets(assets, minAssetsOut);

        $.strategies[fromStrategyId].totalDeposited = $.strategies[fromStrategyId].totalDeposited > assets
            ? $.strategies[fromStrategyId].totalDeposited - assets
            : 0;

        address toVault = $.strategies[toStrategyId].vault;
        address toAsset = $.strategies[toStrategyId].asset;
        IERC20(toAsset).safeIncreaseAllowance(toVault, assets);
        IERC4626(toVault).deposit(assets, $.treasuryCore);
        $.strategies[toStrategyId].totalDeposited += assets;

        emit YieldRebalanced(fromStrategyId, toStrategyId, assets);
    }

    function emergencyWithdrawAll(bytes32 strategyId)
        external
        onlyRole(TREASURY_CONTROLLER_ROLE)
        nonReentrant
    {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        StrategyData storage strategy = $.strategies[strategyId];
        if (!strategy.active) revert StrategyNotActive(strategyId);

        // Withdraw all shares
        uint256 shares =
            IERC20(strategy.vault).balanceOf($.treasuryCore);
        if (shares > 0) {
            ITreasuryYield($.treasuryCore).transferERC20ForYield(
                strategy.vault, address(this), shares
            );
            IERC20(strategy.vault).safeIncreaseAllowance(strategy.vault, shares);
            IERC4626(strategy.vault).redeem(shares, $.treasuryCore, address(this));
            strategy.totalDeposited = 0;
        }
    }

    // ---- Admin ----

    function setPaused(bool paused) external onlyRole(TREASURY_CONTROLLER_ROLE) {
        YieldStorage.layout().paused = paused;
    }

    function setTreasuryCore(address treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury == address(0)) revert ZeroAddress();
        YieldStorage.layout().treasuryCore = treasury;
    }

    // ---- View functions ----

    function getStrategy(bytes32 strategyId) external view returns (StrategyData memory) {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        if ($.strategies[strategyId].vault == address(0)) revert StrategyNotFound(strategyId);
        return $.strategies[strategyId];
    }

    function getPosition(bytes32 positionId) external view returns (PositionData memory) {
        YieldStorage.Layout storage $ = YieldStorage.layout();
        if (!$.positions[positionId].active) revert PositionNotActive(positionId);
        return $.positions[positionId];
    }

    function getStrategyIds() external view returns (bytes32[] memory) {
        return YieldStorage.layout().strategyIds;
    }

    function getTreasuryCore() external view returns (address) {
        return YieldStorage.layout().treasuryCore;
    }

    uint256[47] private __yieldGap;
}
