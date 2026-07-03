// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TreasuryCore} from "../contracts/treasury/TreasuryCore.sol";
import {TreasuryCoreStorage, TransactionStatus, MultiSigTransaction} from "../contracts/treasury/TreasuryCoreStorage.sol";
import {TreasuryFactory, TreasuryDeployment} from "../contracts/factory/TreasuryFactory.sol";
import {StreamingManager} from "../contracts/streaming/StreamingManager.sol";
import {YieldManager} from "../contracts/yield/YieldManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {
    DEFAULT_ADMIN_ROLE,
    SIGNER_ROLE,
    PROPOSER_ROLE,
    EXECUTOR_ROLE,
    CANCELLER_ROLE,
    STRATEGIST_ROLE,
    BUDGET_MANAGER_ROLE,
    MODULE_YIELD,
    MODULE_STREAMING
} from "../contracts/libraries/TreasuryConstants.sol";

contract TreasuryCoreTest is Test {
    TreasuryCore public treasury;
    StreamingManager public streaming;
    YieldManager public yield;
    MockERC20 public usdc;
    MockERC4626 public vault;

    address public admin = makeAddr("admin");
    uint256 public signer1Key = 0xA11CE;
    address public signer1 = vm.addr(signer1Key);
    address public signer2 = makeAddr("signer2");
    address public signer3 = makeAddr("signer3");
    address public budgetOwner = makeAddr("budgetOwner");
    address public recipient = makeAddr("recipient");
    address public alice = makeAddr("alice");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();

        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        // 3/5 multi-sig, 1 day timelock
        TreasuryDeployment memory d =
            factory.deploy(admin, signers, 2, 0); // 0 delay for instant execution in tests

        treasury = d.treasuryCore;
        streaming = d.streamingManager;
        yield = d.yieldManager;

        // Register modules (must be done by admin)
        vm.prank(admin);
        treasury.registerModule(MODULE_YIELD, address(yield));
        vm.prank(admin);
        treasury.registerModule(MODULE_STREAMING, address(streaming));

        // Grant additional roles
        vm.startPrank(admin);
        treasury.grantRole(PROPOSER_ROLE, alice);
        treasury.grantRole(EXECUTOR_ROLE, alice);
        treasury.grantRole(BUDGET_MANAGER_ROLE, budgetOwner);
        yield.grantRole(STRATEGIST_ROLE, alice);
        streaming.grantRole(streaming.STREAM_CREATOR_ROLE(), alice);
        vm.stopPrank();

        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        vault = new MockERC4626(IERC20(address(usdc)), "vUSDC", "vUSDC");

        // Fund treasury with ETH and USDC
        vm.deal(address(treasury), 100 ether);
        usdc.mint(address(treasury), 1_000_000e6);
    }

    // ======== Multi-sig Tests ========

    function testProposeTransaction() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 1 ether, "", 0, 0, "Send 1 ETH to recipient", bytes32(0), bytes32(0), 0
        );

        MultiSigTransaction memory tx_ = treasury.getTransaction(txId);
        assertEq(tx_.value, 1 ether);
    }

    function testMultiSigApprovalWorkflow() public {
        // Propose
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 1 ether, "", 0, 0, "Send 1 ETH", bytes32(0), bytes32(0), 0
        );

        // Approve by signer1
        vm.prank(signer1);
        treasury.approveTransaction(txId);

        MultiSigTransaction memory txState = treasury.getTransaction(txId);
        assertEq(uint256(txState.status), uint256(TransactionStatus.Draft)); // 1/2

        // Approve by signer2 -> reaches threshold 2/2, becomes Ready (minDelay=0)
        vm.prank(signer2);
        treasury.approveTransaction(txId);

        txState = treasury.getTransaction(txId);
        assertEq(uint256(txState.status), uint256(TransactionStatus.Ready)); // threshold met

        // Execute
        uint256 balanceBefore = recipient.balance;
        vm.prank(alice);
        treasury.executeTransaction(txId);
        assertEq(recipient.balance - balanceBefore, 1 ether);
    }

    function testMultiSigWithTimelock() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 1 ether, "", 1 days, 0, "Send 1 ETH with delay", bytes32(0), bytes32(0), 0
        );

        // Approve by 2 signers
        vm.prank(signer1);
        treasury.approveTransaction(txId);
        vm.prank(signer2);
        treasury.approveTransaction(txId);

        MultiSigTransaction memory txTimelock = treasury.getTransaction(txId);
        assertEq(uint256(txTimelock.status), uint256(TransactionStatus.Queued));
        assertGt(txTimelock.executableAt, block.timestamp);

        // Try to execute before timelock expires - should fail
        vm.prank(alice);
        vm.expectRevert();
        treasury.executeTransaction(txId);

        // Fast forward past timelock
        vm.warp(block.timestamp + 2 days);

        // Now execute should succeed
        vm.prank(alice);
        treasury.executeTransaction(txId);
    }

    function testApproveBySignature() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0.5 ether, "", 0, 0, "Gasless test", bytes32(0), bytes32(0), 0
        );

        uint256 nonce = treasury.getNonce(signer1);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ApproveTransaction(uint256 txId,uint256 nonce,uint256 deadline)"),
                txId,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TreasuryCore")),
                keccak256(bytes("1")),
                block.chainid,
                address(treasury)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Key, digest);

        // Use the signature
        treasury.approveBySignature(txId, deadline, v, r, s);

        // Check approval was recorded
        assertTrue(treasury.isApproved(txId, signer1));
    }

    function testRejectTransaction() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 1 ether, "", 0, 0, "Test reject", bytes32(0), bytes32(0), 0
        );

        vm.prank(signer1);
        treasury.approveTransaction(txId);

        // Reject removes approval
        vm.prank(signer1);
        treasury.rejectTransaction(txId);

        assertFalse(treasury.isApproved(txId, signer1));
    }

    function testCancelTransaction() public {
        vm.prank(alice);
        uint256 txId = treasury.proposeTransaction(
            recipient, 1 ether, "", 0, 0, "Test cancel", bytes32(0), bytes32(0), 0
        );

        vm.prank(admin);
        treasury.cancelTransaction(txId);

        MultiSigTransaction memory txCancel = treasury.getTransaction(txId);
        assertEq(uint256(txCancel.status), uint256(TransactionStatus.Cancelled));
    }

    // ======== Signer Management Tests ========

    function testAddRemoveSigner() public {
        address newSigner = makeAddr("newSigner");

        vm.prank(admin);
        treasury.addSigner(newSigner);
        assertTrue(treasury.isActiveSigner(newSigner));

        vm.prank(admin);
        treasury.removeSigner(signer3);
        assertFalse(treasury.isActiveSigner(signer3));
    }

    function testCannotRemoveLastSigner() public {
        // Set threshold to 3 (all signers)
        vm.prank(admin);
        treasury.setGlobalThreshold(3);

        vm.prank(admin);
        vm.expectRevert();
        treasury.removeSigner(signer1); // Cannot remove below threshold
    }

    // ======== Timelock Tests ========

    function testMinDelayRatchet() public {
        vm.prank(admin);
        treasury.setDefaultMinDelay(2 days);

        // Cannot decrease
        vm.prank(admin);
        vm.expectRevert();
        treasury.setDefaultMinDelay(1 days);

        // Admin can force decrease
        vm.prank(admin);
        treasury.forceSetMinDelay(1 hours);
    }

    // ======== Budget Tests ========

    function testCreateAndSpendBudget() public {
        address[] memory approvers = new address[](2);
        approvers[0] = signer1;
        approvers[1] = signer2;

        vm.prank(budgetOwner);
        bytes32 budgetId = treasury.createBudget(
            "Engineering Q3",
            budgetOwner,
            100_000e6,
            uint64(block.timestamp),
            uint64(block.timestamp + 90 days),
            approvers,
            1,
            10_000e6
        );

        // Verify budget was created
        assertEq(treasury.getBudgetAvailable(budgetId), 100_000e6);

        // Propose a transaction linked to the budget — funds are frozen via the hook
        vm.prank(alice);
        treasury.proposeTransaction(
            recipient, 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, 5_000e6),
            0, 0, "Budget spend", bytes32(0), budgetId, 5_000e6
        );

        // Budget funds should now be frozen (pending execution)
        uint256 available = treasury.getBudgetAvailable(budgetId);
        assertEq(available, 100_000e6 - 5_000e6);
    }

    // ======== Streaming Tests ========

    function testCreateAndWithdrawStream() public {
        // Send USDC to treasury and approve streaming
        usdc.mint(address(treasury), 100_000e6);

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient,
            address(usdc),
            10_000e6,
            uint64(block.timestamp),
            0, // no cliff
            uint64(block.timestamp + 30 days),
            true,
            bytes32(0)
        );

        // Fast forward 15 days (halfway)
        vm.warp(block.timestamp + 15 days);

        // Recipient withdraws
        uint256 balanceBefore = usdc.balanceOf(recipient);
        vm.prank(recipient);
        uint256 withdrawn = streaming.withdrawFromStream(streamId);
        assertApproxEqAbs(withdrawn, 5_000e6, 1); // ~half
        assertEq(usdc.balanceOf(recipient) - balanceBefore, withdrawn);
    }

    // ======== Yield Tests ========

    function testYieldStrategyManagement() public {
        vm.prank(alice);
        bytes32 strategyId = yield.addStrategy(
            "USDC Lending", address(vault), address(usdc), 500_000e6, 0 // Low risk
        );

        bytes32[] memory strategyIds = yield.getStrategyIds();
        assertEq(strategyIds.length, 1);
        assertEq(strategyIds[0], strategyId);
    }

    function testDepositToYield() public {
        // Add strategy
        vm.prank(alice);
        bytes32 strategyId = yield.addStrategy(
            "USDC Lending", address(vault), address(usdc), 500_000e6, 0
        );

        // Deposit
        uint256 depositAmount = 100_000e6;
        vm.prank(alice);
        (, uint256 shares) = yield.depositToStrategy(strategyId, depositAmount, 1);

        assertGt(shares, 0);
        assertGt(vault.balanceOf(address(treasury)), 0);
    }

    // ======== Emergency Tests ========

    function testPauseUnpause() public {
        vm.prank(admin);
        treasury.pause();
        assertTrue(treasury.isPaused());

        // Cannot propose while paused
        vm.prank(alice);
        vm.expectRevert();
        treasury.proposeTransaction(recipient, 1 ether, "", 0, 0, "", bytes32(0), bytes32(0), 0);

        vm.prank(admin);
        treasury.unpause();
        assertFalse(treasury.isPaused());
    }

    function testEmergencyShutdown() public {
        vm.prank(admin);
        treasury.triggerEmergencyShutdown();
        assertTrue(treasury.isEmergencyShutdown());

        // Cannot transfer during shutdown
        vm.expectRevert();
        vm.prank(address(streaming));
        treasury.transferETH(payable(recipient), 1 ether);
    }

    // ======== ERC20 Receive ========

    function testReceiveERC20() public {
        usdc.mint(address(treasury), 1_000e6);
        assertEq(treasury.getERC20Balance(address(usdc)), 1_001_000e6);
    }

    // ======== ETH Receive ========

    function testReceiveETH() public {
        uint256 balanceBefore = treasury.getETHBalance();
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        (bool success,) = address(treasury).call{value: 5 ether}("");
        assertTrue(success);
        assertEq(treasury.getETHBalance() - balanceBefore, 5 ether);
    }
}
