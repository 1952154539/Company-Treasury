// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryCore} from "../contracts/treasury/TreasuryCore.sol";
import {YieldManager, StrategyData} from "../contracts/yield/YieldManager.sol";
import {TreasuryFactory, TreasuryDeployment} from "../contracts/factory/TreasuryFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {
    DEFAULT_ADMIN_ROLE,
    STRATEGIST_ROLE,
    TREASURY_CONTROLLER_ROLE,
    MODULE_YIELD
} from "../contracts/libraries/TreasuryConstants.sol";

contract YieldStrategyTest is Test {
    TreasuryCore public treasury;
    YieldManager public yield;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC4626 public usdcVault;
    MockERC4626 public daiVault;

    address public admin = makeAddr("admin");
    address public strategist = makeAddr("strategist");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public controller = makeAddr("controller");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        TreasuryDeployment memory d = factory.deploy(admin, signers, 2, 0);
        treasury = d.treasuryCore;
        yield = d.yieldManager;

        vm.startPrank(admin);
        treasury.registerModule(MODULE_YIELD, address(yield));
        yield.grantRole(STRATEGIST_ROLE, strategist);
        yield.grantRole(TREASURY_CONTROLLER_ROLE, controller);
        vm.stopPrank();

        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);
        usdcVault = new MockERC4626(IERC20(address(usdc)), "vUSDC", "vUSDC");
        daiVault = new MockERC4626(IERC20(address(dai)), "vDAI", "vDAI");

        usdc.mint(address(treasury), 10_000_000e6);
        dai.mint(address(treasury), 1_000_000e18);
        vm.deal(address(treasury), 1000 ether);
    }

    // ---- Strategy Lifecycle ----

    function test_AddAndRemoveStrategy() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "USDC Lending", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        bytes32[] memory ids = yield.getStrategyIds();
        assertEq(ids.length, 1);

        vm.prank(strategist);
        yield.removeStrategy(strategyId);

        bytes32[] memory idsAfter = yield.getStrategyIds();
        assertEq(idsAfter.length, 1);

        StrategyData memory s = yield.getStrategy(strategyId);
        assertFalse(s.active);
    }

    function test_CannotAddVaultWithWrongAsset() public {
        // usdcVault.asset() returns usdc, but we claim it's dai
        vm.prank(strategist);
        vm.expectRevert();
        yield.addStrategy("Wrong Asset", address(usdcVault), address(dai), 1_000_000e6, 0);
    }

    // ---- Deposit / Withdraw ----

    function test_DepositAndGetShares() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "USDC Lending", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        uint256 depositAmount = 500_000e6;
        vm.prank(strategist);
        (bytes32 positionId, uint256 shares) = yield.depositToStrategy(strategyId, depositAmount, 1);

        assertGt(shares, 0);
        assertGt(usdcVault.balanceOf(address(treasury)), 0);

        StrategyData memory s = yield.getStrategy(strategyId);
        assertEq(s.totalDeposited, depositAmount);
    }

    function test_DepositExceedsAllocationCap() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Capped", address(usdcVault), address(usdc), 100_000e6, 0
        );

        vm.prank(strategist);
        vm.expectRevert();
        yield.depositToStrategy(strategyId, 200_000e6, 1);
    }

    function test_MultipleDepositsAccumulate() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Multi Deposit", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        vm.prank(strategist);
        yield.depositToStrategy(strategyId, 100_000e6, 1);

        StrategyData memory s1 = yield.getStrategy(strategyId);
        assertEq(s1.totalDeposited, 100_000e6);

        vm.prank(strategist);
        yield.depositToStrategy(strategyId, 200_000e6, 1);

        StrategyData memory s2 = yield.getStrategy(strategyId);
        assertEq(s2.totalDeposited, 300_000e6);
    }

    // ---- Slippage Protection ----

    function test_SlippageProtectionFails() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Slippage Test", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        vm.prank(strategist);
        (bytes32 positionId, uint256 shares) = yield.depositToStrategy(strategyId, 100_000e6, 1);

        vm.prank(strategist);
        vm.expectRevert();
        yield.withdrawFromStrategy(positionId, shares, type(uint256).max);
    }

    // ---- Harvest ----

    function test_HarvestYield() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "No Yield", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        vm.prank(strategist);
        yield.depositToStrategy(strategyId, 100_000e6, 1);

        vm.prank(strategist);
        uint256 harvested = yield.harvestYield(strategyId);
        assertEq(harvested, 0, "mock vault 1:1 means no yield");
    }

    // ---- Emergency Withdraw ----

    function test_EmergencyWithdrawAll() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Emergency Test", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        vm.prank(strategist);
        yield.depositToStrategy(strategyId, 100_000e6, 1);

        // Treasury holds vault shares; emergencyWithdrawAll transfers shares to YieldManager,
        // then redeems them back to TreasuryCore. This requires the shares to be transferable.
        // MockERC4626 extends MockERC20 which supports transfers.
        // The transfer goes TreasuryCore → YieldManager, then YieldManager redeems → TreasuryCore.
        vm.prank(controller);
        yield.emergencyWithdrawAll(strategyId);

        StrategyData memory s = yield.getStrategy(strategyId);
        assertEq(s.totalDeposited, 0, "emergency withdraw resets deposited");
        assertTrue(s.active, "strategy remains active after emergency withdraw");
    }

    function test_NonControllerCannotEmergencyWithdraw() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "No Emergency", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        vm.prank(strategist);
        yield.depositToStrategy(strategyId, 100_000e6, 1);

        vm.prank(signer1);
        vm.expectRevert();
        yield.emergencyWithdrawAll(strategyId);
    }

    // ---- Rebalance ----

    function test_RebalanceBetweenStrategies() public {
        vm.prank(strategist);
        bytes32 strategyId1 = yield.addStrategy(
            "From Strategy", address(usdcVault), address(usdc), 1_000_000e6, 0
        );
        vm.prank(strategist);
        bytes32 strategyId2 = yield.addStrategy(
            "To Strategy", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        uint256 depositAmount = 100_000e6;
        vm.prank(strategist);
        (, uint256 shares) = yield.depositToStrategy(strategyId1, depositAmount, 1);

        StrategyData memory beforeFrom = yield.getStrategy(strategyId1);
        StrategyData memory beforeTo = yield.getStrategy(strategyId2);
        assertEq(beforeFrom.totalDeposited, depositAmount);
        assertEq(beforeTo.totalDeposited, 0);

        vm.prank(strategist);
        yield.rebalance(strategyId1, strategyId2, shares, 0);

        StrategyData memory afterFrom = yield.getStrategy(strategyId1);
        StrategyData memory afterTo = yield.getStrategy(strategyId2);
        assertEq(afterFrom.totalDeposited, 0, "from strategy emptied");
        assertEq(afterTo.totalDeposited, depositAmount, "to strategy received");
    }

    // ---- Pause Contract ----

    function test_ContractPauseBlocksDeposits() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Pause Test", address(usdcVault), address(usdc), 1_000_000e6, 0
        );

        vm.prank(controller);
        yield.setPaused(true);

        vm.prank(strategist);
        vm.expectRevert();
        yield.depositToStrategy(strategyId, 100_000e6, 1);

        vm.prank(controller);
        yield.setPaused(false);

        vm.prank(strategist);
        yield.depositToStrategy(strategyId, 100_000e6, 1);
    }

    // ---- Multi-Strategy with Different Risk Levels ----

    function test_MultipleStrategiesVaryingRisk() public {
        vm.prank(strategist);
        yield.addStrategy("Low Risk", address(usdcVault), address(usdc), 500_000e6, 0);
        vm.prank(strategist);
        yield.addStrategy("Med Risk", address(daiVault), address(dai), 500_000e18, 1);
        vm.prank(strategist);
        yield.addStrategy("High Risk", address(usdcVault), address(usdc), 500_000e6, 2);

        bytes32[] memory ids = yield.getStrategyIds();
        assertEq(ids.length, 3);
    }

    // ---- View Functions ----

    function test_StrategyViewFunctions() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Query Test", address(usdcVault), address(usdc), 500_000e6, 0
        );

        StrategyData memory s = yield.getStrategy(strategyId);
        assertEq(s.name, "Query Test");
        assertEq(s.vault, address(usdcVault));
        assertEq(s.asset, address(usdc));
        assertEq(s.allocationCap, 500_000e6);
        assertEq(s.totalDeposited, 0);
        assertEq(s.riskLevel, 0);
        assertTrue(s.active);
    }

    // ---- Update Cap ----

    function test_UpdateAllocationCap() public {
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "Cap Update", address(usdcVault), address(usdc), 500_000e6, 0
        );

        vm.prank(strategist);
        yield.updateStrategyCap(strategyId, 1_000_000e6);

        StrategyData memory s = yield.getStrategy(strategyId);
        assertEq(s.allocationCap, 1_000_000e6);
    }

    // ---- Non-strategist cannot add ----

    function test_NonStrategistCannotAddStrategy() public {
        vm.prank(signer1);
        vm.expectRevert();
        yield.addStrategy("Unauthorized", address(usdcVault), address(usdc), 100_000e6, 0);
    }
}
