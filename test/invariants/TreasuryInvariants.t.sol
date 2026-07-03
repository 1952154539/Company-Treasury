// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryCore} from "../../contracts/treasury/TreasuryCore.sol";
import {TreasuryCoreStorage, BudgetStatus, Budget} from "../../contracts/treasury/TreasuryCoreStorage.sol";
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
    CANCELLER_ROLE,
    BUDGET_MANAGER_ROLE,
    STRATEGIST_ROLE,
    MODULE_YIELD,
    MODULE_STREAMING
} from "../../contracts/libraries/TreasuryConstants.sol";

contract TreasuryInvariantsTest is Test {
    TreasuryCore public treasury;
    StreamingManager public streaming;
    YieldManager public yield;
    MockERC20 public usdc;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public recipient = makeAddr("recipient");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        TreasuryDeployment memory d = factory.deploy(admin, signers, 2, 0);
        treasury = d.treasuryCore;
        streaming = d.streamingManager;
        yield = d.yieldManager;

        vm.startPrank(admin);
        treasury.registerModule(MODULE_YIELD, address(yield));
        treasury.registerModule(MODULE_STREAMING, address(streaming));
        treasury.grantRole(PROPOSER_ROLE, alice);
        treasury.grantRole(EXECUTOR_ROLE, alice);
        treasury.grantRole(BUDGET_MANAGER_ROLE, alice);
        treasury.grantRole(CANCELLER_ROLE, alice);
        yield.grantRole(STRATEGIST_ROLE, alice);
        streaming.grantRole(streaming.STREAM_CREATOR_ROLE(), alice);
        vm.stopPrank();

        usdc = new MockERC20("USDC", "USDC", 6);
        usdc.mint(address(treasury), 1_000_000_000e6);
        vm.deal(address(treasury), 1000 ether);
    }

    /// @dev Invariant: totalAllocated >= totalSpent + totalFrozen for every budget
    function testInvariant_BudgetAccounting() public {
        address[] memory approvers = new address[](1);
        approvers[0] = alice;

        vm.startPrank(alice);
        bytes32 budgetId = treasury.createBudget(
            "Test", alice, 100_000e6, uint64(block.timestamp), uint64(block.timestamp + 365 days),
            approvers, 1, 50_000e6
        );
        vm.stopPrank();

        // Propose with budget link — freezes 30k
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "spend1", bytes32(0), budgetId, 30_000e6
        );

        // Execute — moves frozen to spent
        vm.prank(signer1);
        treasury.approveTransaction(txId);
        vm.prank(signer2);
        treasury.approveTransaction(txId);
        vm.prank(alice);
        treasury.executeTransaction(txId);

        Budget memory budget = treasury.getBudget(budgetId);
        assertEq(budget.totalAllocated, 100_000e6);
        assertEq(budget.totalSpent, 30_000e6);
        assertEq(budget.totalFrozen, 0);
        // Invariant holds: 100k >= 30k + 0
        assertGe(budget.totalAllocated, budget.totalSpent + budget.totalFrozen);
    }

    /// @dev Invariant: cancelled transaction releases frozen budget funds
    function testInvariant_CancellationReleasesBudget() public {
        address[] memory approvers = new address[](1);
        approvers[0] = alice;

        vm.startPrank(alice);
        bytes32 budgetId = treasury.createBudget(
            "CancelTest", alice, 100_000e6, uint64(block.timestamp), uint64(block.timestamp + 365 days),
            approvers, 1, 100_000e6
        );
        vm.stopPrank();

        // Propose with budget link — freeze
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "cancel spend", bytes32(0), budgetId, 20_000e6
        );

        uint256 frozenAvailable = treasury.getBudgetAvailable(budgetId);
        assertEq(frozenAvailable, 80_000e6, "20k should be frozen");

        // Cancel — funds should be released
        vm.prank(alice);
        treasury.cancelTransaction(txId);

        uint256 releasedAvailable = treasury.getBudgetAvailable(budgetId);
        assertEq(releasedAvailable, 100_000e6, "frozen funds should be released on cancel");
    }

    /// @dev Invariant: threshold cannot exceed active signer count
    function testInvariant_ThresholdBoundary() public view {
        uint256 signerCount = treasury.getActiveSignerCount();
        uint256 threshold = treasury.getGlobalThreshold();
        assertGe(signerCount, threshold, "threshold must not exceed signer count");
    }

    /// @dev Invariant: emergency shutdown prevents all state-changing operations
    function testInvariant_ShutdownBlocksOperations() public {
        vm.prank(admin);
        treasury.triggerEmergencyShutdown();

        // Cannot propose
        vm.prank(alice);
        vm.expectRevert();
        treasury.proposeTransaction(recipient, 0, "", 0, 0, "", bytes32(0), bytes32(0), 0);

        // Cannot transfer (via streaming module)
        vm.expectRevert();
        vm.prank(address(streaming));
        treasury.transferETH(payable(recipient), 1 ether);
    }

    /// @dev Invariant: stream totalAmount = remainingBalance + withdrawn by recipient
    function testInvariant_StreamBalanceAccounting() public {
        usdc.mint(address(treasury), 100_000e6);
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = startTime + 30 days;

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient, address(usdc), 10_000e6, startTime, 0, endTime, true, bytes32(0)
        );

        // Warp to 50%
        vm.warp(startTime + 15 days);

        uint256 balanceBefore = usdc.balanceOf(recipient);
        vm.prank(recipient);
        streaming.withdrawFromStream(streamId);
        uint256 received = usdc.balanceOf(recipient) - balanceBefore;

        // Invariant: received ≈ half of total (linear vesting)
        assertApproxEqAbs(received, 5_000e6, 1);
    }

    /// @dev Invariant: module registry only modified by admin
    function testInvariant_ModuleRegistryAuth() public {
        address existingModule = treasury.getModuleAddress(MODULE_STREAMING);
        assertEq(existingModule, address(streaming));

        // Non-admin cannot register
        vm.prank(alice);
        vm.expectRevert();
        treasury.registerModule(keccak256("NEW_MODULE"), alice);

        // Non-admin cannot revoke
        vm.prank(alice);
        vm.expectRevert();
        treasury.revokeModule(MODULE_STREAMING);
    }

    /// @dev Invariant: signer list and active count stay consistent
    function testInvariant_SignerConsistency() public view {
        address[] memory signers = treasury.getSignerList();
        uint256 activeCount = treasury.getActiveSignerCount();
        uint256 actualActive = 0;
        for (uint256 i = 0; i < signers.length; i++) {
            if (treasury.isActiveSigner(signers[i])) actualActive++;
        }
        assertEq(activeCount, actualActive, "active count must match isActiveSigner");
    }
}
