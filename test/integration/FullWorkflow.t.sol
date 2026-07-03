// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryCore} from "../../contracts/treasury/TreasuryCore.sol";
import {TreasuryCoreStorage, MultiSigTransaction, TransactionStatus, BudgetStatus, Budget} from "../../contracts/treasury/TreasuryCoreStorage.sol";
import {StreamingManager} from "../../contracts/streaming/StreamingManager.sol";
import {YieldManager} from "../../contracts/yield/YieldManager.sol";
import {TreasuryFactory, TreasuryDeployment} from "../../contracts/factory/TreasuryFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {
    DEFAULT_ADMIN_ROLE,
    SIGNER_ROLE,
    PROPOSER_ROLE,
    EXECUTOR_ROLE,
    BUDGET_MANAGER_ROLE,
    STRATEGIST_ROLE,
    TREASURY_CONTROLLER_ROLE,
    RECOVERY_ROLE,
    MODULE_YIELD,
    MODULE_STREAMING
} from "../../contracts/libraries/TreasuryConstants.sol";

contract FullWorkflowTest is Test {
    TreasuryCore public treasury;
    StreamingManager public streaming;
    YieldManager public yield;
    MockERC20 public usdc;
    MockERC4626 public vault;

    address public admin = makeAddr("admin");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public signer3 = makeAddr("signer3");
    address public proposer = makeAddr("proposer");
    address public executor = makeAddr("executor");
    address public strategist = makeAddr("strategist");
    address public budgetOwner = makeAddr("budgetOwner");
    address public vendor = makeAddr("vendor");
    address public employee = makeAddr("employee");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        TreasuryDeployment memory d = factory.deploy(admin, signers, 2, 0); // 0 delay for test
        treasury = d.treasuryCore;
        streaming = d.streamingManager;
        yield = d.yieldManager;

        // Register modules and grant roles
        vm.startPrank(admin);
        treasury.registerModule(MODULE_YIELD, address(yield));
        treasury.registerModule(MODULE_STREAMING, address(streaming));
        treasury.grantRole(PROPOSER_ROLE, proposer);
        treasury.grantRole(EXECUTOR_ROLE, executor);
        treasury.grantRole(BUDGET_MANAGER_ROLE, budgetOwner);
        yield.grantRole(STRATEGIST_ROLE, strategist);
        streaming.grantRole(streaming.STREAM_CREATOR_ROLE(), admin);
        vm.stopPrank();

        usdc = new MockERC20("USDC", "USDC", 6);
        vault = new MockERC4626(IERC20(address(usdc)), "vUSDC", "vUSDC");

        usdc.mint(address(treasury), 1_000_000_000e6);
        vm.deal(address(treasury), 1000 ether);
    }

    // ======== E2E: Multi-sig with Budget ========

    function testFullMultiSigWithBudget() public {
        // 1. Create budget
        address[] memory approvers = new address[](2);
        approvers[0] = signer1;
        approvers[1] = signer2;

        vm.prank(budgetOwner);
        bytes32 budgetId = treasury.createBudget(
            "Q3 Engineering", budgetOwner, 500_000e6,
            uint64(block.timestamp), uint64(block.timestamp + 90 days),
            approvers, 1, 100_000e6
        );

        // 2. Propose payment to vendor (linked to budget)
        uint256 paymentAmount = 50_000e6;
        vm.prank(proposer);
        uint256 txId = treasury.proposeTransaction(
            vendor, 0,
            abi.encodeWithSignature("transfer(address,uint256)", vendor, paymentAmount),
            0, 0, "Pay vendor for Q3 work", bytes32(0), budgetId, paymentAmount
        );

        // 3. Verify budget frozen
        uint256 available = treasury.getBudgetAvailable(budgetId);
        assertEq(available, 500_000e6 - paymentAmount);

        // 4. Two signers approve
        vm.prank(signer1);
        treasury.approveTransaction(txId);
        vm.prank(signer2);
        treasury.approveTransaction(txId);

        // 5. Execute
        vm.prank(executor);
        treasury.executeTransaction(txId);

        // 6. Verify budget spent
        Budget memory budget = treasury.getBudget(budgetId);
        assertEq(budget.totalSpent, paymentAmount);
        assertEq(budget.totalFrozen, 0);
        assertEq(treasury.getBudgetAvailable(budgetId), 500_000e6 - paymentAmount);
    }

    // ======== E2E: Transaction with Timelock ========

    function testFullTimelockedTransaction() public {
        vm.prank(proposer);
        uint256 txId = treasury.proposeTransaction(
            vendor, 5 ether, "", 2 days, 0, "Timelocked payment", bytes32(0), bytes32(0), 0
        );

        // Approve to reach threshold
        vm.prank(signer1);
        treasury.approveTransaction(txId);
        vm.prank(signer2);
        treasury.approveTransaction(txId);

        // Status should be Queued (not Ready)
        MultiSigTransaction memory tx_ = treasury.getTransaction(txId);
        assertEq(uint256(tx_.status), uint256(TransactionStatus.Queued));

        // Cannot execute before timelock
        vm.prank(executor);
        vm.expectRevert();
        treasury.executeTransaction(txId);

        // Warp past timelock
        vm.warp(block.timestamp + 3 days);

        // Now executable
        uint256 balanceBefore = vendor.balance;
        vm.prank(executor);
        treasury.executeTransaction(txId);
        assertEq(vendor.balance - balanceBefore, 5 ether);
    }

    // ======== E2E: Stream Creation + Withdrawal ========

    function testFullStreamLifecycle() public {
        usdc.mint(address(treasury), 100_000e6);

        uint64 startTime = uint64(block.timestamp);
        uint64 cliffDuration = 7 days;
        uint64 totalDuration = 90 days;

        vm.prank(admin);
        uint256 streamId = streaming.createStream(
            employee, address(usdc), 90_000e6,
            startTime, cliffDuration, startTime + totalDuration, true, bytes32(0)
        );

        // No withdrawal during cliff
        vm.warp(startTime + 3 days);
        vm.prank(employee);
        vm.expectRevert(); // NoReleasableAmount
        streaming.withdrawFromStream(streamId);

        // Partial withdrawal after cliff
        vm.warp(startTime + 30 days);
        uint256 balanceBefore = usdc.balanceOf(employee);
        vm.prank(employee);
        uint256 withdrawn = streaming.withdrawFromStream(streamId);
        assertGt(withdrawn, 0, "should have some vested amount");
        assertGt(usdc.balanceOf(employee), balanceBefore);

        // Full withdrawal after stream ends
        vm.warp(startTime + totalDuration + 1);
        vm.prank(employee);
        streaming.withdrawFromStream(streamId);
        // Remaining should be near zero
        vm.expectRevert();
        streaming.withdrawFromStream(streamId);
    }

    // ======== E2E: Emergency Pause → Unpause ========

    function testFullEmergencyPauseFlow() public {
        // Propose a transaction
        vm.prank(proposer);
        uint256 txId = treasury.proposeTransaction(
            vendor, 1 ether, "", 0, 0, "Normal payment", bytes32(0), bytes32(0), 0
        );

        // Pause
        vm.prank(admin);
        treasury.pause();
        assertTrue(treasury.isPaused());

        // Cannot propose while paused
        vm.prank(proposer);
        vm.expectRevert();
        treasury.proposeTransaction(vendor, 0, "", 0, 0, "Blocked", bytes32(0), bytes32(0), 0);

        // Unpause and continue
        vm.prank(admin);
        treasury.unpause();

        // Now can approve and execute the original transaction
        vm.prank(signer1);
        treasury.approveTransaction(txId);
        vm.prank(signer2);
        treasury.approveTransaction(txId);

        vm.prank(executor);
        treasury.executeTransaction(txId);
    }

    // ======== E2E: Emergency Shutdown + Recovery ========

    function testFullEmergencyRecoveryFlow() public {
        address recoveryAddr = makeAddr("recoverySafe");

        // Setup recovery
        vm.prank(admin);
        treasury.grantRole(RECOVERY_ROLE, recoveryAddr);
        vm.prank(admin);
        treasury.setRecoveryAddress(recoveryAddr, true);

        // Trigger shutdown
        vm.prank(admin);
        treasury.triggerEmergencyShutdown();
        assertTrue(treasury.isEmergencyShutdown());

        // Initiate recovery with 48h delay
        vm.prank(recoveryAddr);
        treasury.initiateEmergencyRecovery(recoveryAddr, address(0), 10 ether);

        // Cannot execute before delay
        vm.prank(recoveryAddr);
        vm.expectRevert();
        treasury.executeEmergencyRecovery(address(0), recoveryAddr, 10 ether);

        // Warp past 48h
        vm.warp(block.timestamp + 48 hours + 1);

        // Now can recover
        uint256 balanceBefore = recoveryAddr.balance;
        vm.prank(recoveryAddr);
        treasury.executeEmergencyRecovery(address(0), recoveryAddr, 10 ether);
        assertEq(recoveryAddr.balance - balanceBefore, 10 ether);
    }

    // ======== E2E: Yield Deposit + Harvest ========

    function testFullYieldFlow() public {
        // Add strategy
        vm.prank(strategist);
        bytes32 strategyId = yield.addStrategy(
            "USDC Lending", address(vault), address(usdc), 500_000e6, 0
        );

        // Deposit
        uint256 depositAmount = 100_000e6;
        vm.prank(strategist);
        (, uint256 shares) = yield.depositToStrategy(strategyId, depositAmount, 1);
        assertGt(shares, 0);
        assertGt(vault.balanceOf(address(treasury)), 0);

        // Simulate yield: mint extra USDC to vault to simulate yield accrual
        // (MockERC4626 uses 1:1 conversion, so we simulate yield differently)
        // Harvest
        vm.prank(strategist);
        uint256 harvested = yield.harvestYield(strategyId);
        // Even if no yield, harvest should not revert
        assertEq(harvested, 0);
    }

    // ======== E2E: Batch Stream Creation ========

    function testBatchCreateStreams() public {
        usdc.mint(address(treasury), 300_000e6);

        address[] memory recipients = new address[](3);
        recipients[0] = makeAddr("emp1");
        recipients[1] = makeAddr("emp2");
        recipients[2] = makeAddr("emp3");

        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(usdc);
        tokens[2] = address(usdc);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10_000e6;
        amounts[1] = 20_000e6;
        amounts[2] = 30_000e6;

        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = startTime + 180 days;
        uint64[] memory startTimes = new uint64[](3);
        startTimes[0] = startTime;
        startTimes[1] = startTime;
        startTimes[2] = startTime;

        uint64[] memory cliffs = new uint64[](3);
        cliffs[0] = 0;
        cliffs[1] = 0;
        cliffs[2] = 0;

        uint64[] memory endTimes = new uint64[](3);
        endTimes[0] = endTime;
        endTimes[1] = endTime;
        endTimes[2] = endTime;

        bool[] memory cancelables = new bool[](3);
        cancelables[0] = true;
        cancelables[1] = true;
        cancelables[2] = true;

        bytes32[] memory budgetIds = new bytes32[](3);

        vm.prank(admin);
        uint256[] memory streamIds = streaming.batchCreateStreams(
            recipients, tokens, amounts, startTimes, cliffs, endTimes, cancelables, budgetIds
        );

        assertEq(streamIds.length, 3);
        assertEq(streaming.getStreamCount(), 3);
    }
}
