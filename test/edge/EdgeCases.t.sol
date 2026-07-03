// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryCore} from "../../contracts/treasury/TreasuryCore.sol";
import {TreasuryCoreStorage, TransactionStatus, MultiSigTransaction} from "../../contracts/treasury/TreasuryCoreStorage.sol";
import {StreamingManager} from "../../contracts/streaming/StreamingManager.sol";
import {TreasuryFactory, TreasuryDeployment} from "../../contracts/factory/TreasuryFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {
    DEFAULT_ADMIN_ROLE,
    SIGNER_ROLE,
    PROPOSER_ROLE,
    EXECUTOR_ROLE,
    BUDGET_MANAGER_ROLE,
    MODULE_STREAMING
} from "../../contracts/libraries/TreasuryConstants.sol";

contract EdgeCasesTest is Test {
    TreasuryCore public treasury;
    StreamingManager public streaming;
    MockERC20 public usdc;

    address public admin = makeAddr("admin");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public alice = makeAddr("alice");
    address public recipient = makeAddr("recipient");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;
        TreasuryDeployment memory d = factory.deploy(admin, signers, 2, 0);
        treasury = d.treasuryCore;
        streaming = d.streamingManager;

        vm.deal(address(treasury), 100 ether);
        vm.startPrank(admin);
        treasury.registerModule(MODULE_STREAMING, address(streaming));
        treasury.grantRole(PROPOSER_ROLE, alice);
        treasury.grantRole(EXECUTOR_ROLE, alice);
        treasury.grantRole(BUDGET_MANAGER_ROLE, alice);
        streaming.grantRole(streaming.STREAM_CREATOR_ROLE(), alice);
        vm.stopPrank();

        usdc = new MockERC20("USDC", "USDC", 6);
        usdc.mint(address(treasury), 1_000_000e6);
    }

    // ---- Threshold boundary ----

    function testEdge_ThresholdAtSignerCount() public {
        // Set threshold = 2 (current signer count)
        vm.prank(admin);
        treasury.setGlobalThreshold(2);
        assertEq(treasury.getGlobalThreshold(), 2);

        // Cannot set threshold > signer count
        vm.prank(admin);
        vm.expectRevert();
        treasury.setGlobalThreshold(3);
    }

    function testEdge_RemoveSignerAtThreshold() public {
        // Set threshold to 2, try to remove signer (would drop active to 1)
        vm.prank(admin);
        treasury.setGlobalThreshold(2);
        vm.prank(admin);
        vm.expectRevert(); // CannotRemoveLastSigner
        treasury.removeSigner(signer1);
    }

    // ---- Zero/minimal values ----

    function testEdge_ZeroValueTransaction() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "Zero value", bytes32(0), bytes32(0), 0
        );
        MultiSigTransaction memory tx_ = treasury.getTransaction(txId);
        assertEq(tx_.value, 0);
    }

    function testEdge_MinimumBudgetAllocation() public {
        address[] memory approvers = new address[](1);
        approvers[0] = signer1;

        vm.prank(alice);
        bytes32 budgetId = treasury.createBudget(
            "Min Budget", alice, 1,
            uint64(block.timestamp), uint64(block.timestamp + 365 days),
            approvers, 1, 1
        );
        assertEq(treasury.getBudgetAvailable(budgetId), 1);
    }

    // ---- Multiple budgets ----

    function testEdge_MultipleBudgets() public {
        address[] memory approvers = new address[](1);
        approvers[0] = signer1;

        vm.startPrank(alice);
        treasury.createBudget("B1", alice, 1000e6, uint64(block.timestamp), uint64(block.timestamp + 90 days), approvers, 1, 500e6);
        treasury.createBudget("B2", alice, 2000e6, uint64(block.timestamp), uint64(block.timestamp + 90 days), approvers, 1, 1000e6);
        vm.stopPrank();

        bytes32[] memory ids = treasury.getBudgetIds();
        assertEq(ids.length, 2);
    }

    // ---- Future budget start ----

    function testEdge_FutureBudgetStart() public {
        address[] memory approvers = new address[](1);
        approvers[0] = signer1;

        uint64 futureStart = uint64(block.timestamp + 30 days);
        vm.prank(alice);
        bytes32 budgetId = treasury.createBudget(
            "Future Budget", alice, 1000e6,
            futureStart, uint64(block.timestamp + 365 days),
            approvers, 1, 500e6
        );

        // Can't spend before start
        vm.prank(alice);
        vm.expectRevert();
        treasury.proposeTransaction(recipient, 0, "", 0, 0, "Early", bytes32(0), budgetId, 100e6);
    }

    // ---- Double approval prevention & rejection ----

    function testEdge_BitmapCollision() public {
        // Propose and approve by signer1
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "Bitmap test", bytes32(0), bytes32(0), 0
        );

        vm.prank(signer1);
        treasury.approveTransaction(txId);
        assertTrue(treasury.isApproved(txId, signer1));

        // Reject removes approval
        vm.prank(signer1);
        treasury.rejectTransaction(txId);
        assertFalse(treasury.isApproved(txId, signer1));

        // Re-approve should work
        vm.prank(signer1);
        treasury.approveTransaction(txId);
        assertTrue(treasury.isApproved(txId, signer1));
    }

    // ---- Budget close with frozen funds ----

    function testEdge_CannotCloseBudgetWithPendingTx() public {
        address[] memory approvers = new address[](1);
        approvers[0] = signer1;

        vm.prank(alice);
        bytes32 budgetId = treasury.createBudget(
            "Blocked Budget", alice, 1000e6,
            uint64(block.timestamp), uint64(block.timestamp + 365 days),
            approvers, 1, 500e6
        );

        // Freeze some funds
        vm.prank(alice);
        treasury.proposeTransaction(recipient, 0, "", 0, 0, "Spend", bytes32(0), budgetId, 200e6);

        // Cannot close with frozen funds
        vm.prank(alice);
        vm.expectRevert();
        treasury.closeBudget(budgetId);
    }

    // ---- Unauthorized access ----

    function testEdge_UnauthorizedSignerCannotApprove() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "Auth test", bytes32(0), bytes32(0), 0
        );

        // alice is not a signer
        vm.prank(alice);
        vm.expectRevert();
        treasury.approveTransaction(txId);
    }

    function testEdge_UnauthorizedCannotExecute() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "Execute test", bytes32(0), bytes32(0), 0
        );

        // signer1 approves but signer2 hasn't → only 1/2
        vm.prank(signer1);
        treasury.approveTransaction(txId);

        // signer1 is not an executor
        vm.prank(signer1);
        vm.expectRevert();
        treasury.executeTransaction(txId);
    }
}
