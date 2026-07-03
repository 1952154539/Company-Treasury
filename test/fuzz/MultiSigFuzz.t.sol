// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryCore} from "../../contracts/treasury/TreasuryCore.sol";
import {TreasuryCoreStorage, MultiSigTransaction, TransactionStatus} from "../../contracts/treasury/TreasuryCoreStorage.sol";
import {TreasuryFactory, TreasuryDeployment} from "../../contracts/factory/TreasuryFactory.sol";
import {
    DEFAULT_ADMIN_ROLE,
    SIGNER_ROLE,
    PROPOSER_ROLE,
    EXECUTOR_ROLE,
    CANCELLER_ROLE,
    BUDGET_MANAGER_ROLE
} from "../../contracts/libraries/TreasuryConstants.sol";

contract MultiSigFuzzTest is Test {
    TreasuryCore public treasury;
    address public admin = makeAddr("admin");
    address public proposer = makeAddr("proposer");
    address public executor = makeAddr("executor");
    address public recipient = makeAddr("recipient");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();
        address[] memory signers = new address[](1);
        signers[0] = admin;
        TreasuryDeployment memory d = factory.deploy(admin, signers, 1, 0);
        treasury = d.treasuryCore;

        // Fund the treasury
        vm.deal(address(treasury), 1000 ether);

        vm.startPrank(admin);
        treasury.grantRole(PROPOSER_ROLE, proposer);
        treasury.grantRole(EXECUTOR_ROLE, executor);
        treasury.grantRole(BUDGET_MANAGER_ROLE, admin);
        vm.stopPrank();
    }

    /// @dev Fuzz: any valid combination of signer count + threshold should work
    function testFuzz_SignerCountAndThreshold(
        uint8 signerCount,
        uint8 threshold
    ) public {
        signerCount = uint8(bound(signerCount, 2, 15));
        threshold = uint8(bound(threshold, 1, signerCount));

        // Add signers
        for (uint256 i = 0; i < signerCount; i++) {
            address signer = makeAddr(string(abi.encodePacked("signer", i)));
            vm.prank(admin);
            treasury.addSigner(signer);
        }

        vm.prank(admin);
        treasury.setGlobalThreshold(threshold);

        assertEq(treasury.getGlobalThreshold(), threshold);
        assertEq(treasury.getActiveSignerCount(), signerCount + 1); // +1 for admin from setUp
    }

    /// @dev Fuzz: proposal with budget link should freeze correct amount
    function testFuzz_BudgetFreezeAmount(
        uint256 budgetAllocation,
        uint256 spendAmount
    ) public {
        budgetAllocation = bound(budgetAllocation, 1e6, 1_000_000e6);
        spendAmount = bound(spendAmount, 1, budgetAllocation);

        address[] memory approvers = new address[](1);
        approvers[0] = admin;

        vm.prank(admin);
        bytes32 budgetId = treasury.createBudget(
            "Fuzz Budget", admin, budgetAllocation,
            uint64(block.timestamp), uint64(block.timestamp + 365 days),
            approvers, 1, spendAmount
        );

        // Propose with budget link
        vm.prank(proposer);
        treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "Budget spend fuzz", bytes32(0), budgetId, spendAmount
        );

        uint256 available = treasury.getBudgetAvailable(budgetId);
        assertEq(available, budgetAllocation - spendAmount, "budget freeze mismatch");
    }

    /// @dev Fuzz: random approval order should eventually reach threshold
    function testFuzz_RandomApprovalOrder(
        uint8 signerCount,
        uint8 threshold
    ) public {
        signerCount = uint8(bound(signerCount, 2, 10));
        threshold = uint8(bound(threshold, 2, signerCount));

        // Setup signers
        address[] memory signers = new address[](signerCount);
        for (uint256 i = 0; i < signerCount; i++) {
            signers[i] = makeAddr(string(abi.encodePacked("signer", i)));
            vm.prank(admin);
            treasury.addSigner(signers[i]);
        }
        vm.prank(admin);
        treasury.setGlobalThreshold(threshold);

        // Propose
        vm.prank(proposer);
        uint256 txId = treasury.proposeTransaction(
            recipient, 1 ether, "", 0, 0, "Random order", bytes32(0), bytes32(0), 0
        );

        // Approve in random order (using salt to shuffle)
        uint256 salt = uint256(keccak256(abi.encodePacked("salt")));
        for (uint256 i = 0; i < signerCount; i++) {
            uint256 idx = (salt + i * 17 + 3) % signerCount; // pseudo-random
            if (i < threshold) {
                vm.prank(signers[idx]);
                treasury.approveTransaction(txId);
            }
        }

        MultiSigTransaction memory tx_ = treasury.getTransaction(txId);
        assertEq(uint256(tx_.status), uint256(TransactionStatus.Ready), "should be ready after threshold");
        assertEq(tx_.approvalCount, threshold, "approval count should equal threshold");
    }

    /// @dev Fuzz: bitmap correctly tracks approval for randomized signer indices
    function testFuzz_BitmapCorrectness(
        uint8 signerCount,
        uint8 approveIndex
    ) public {
        signerCount = uint8(bound(signerCount, 2, 10));
        approveIndex = uint8(bound(approveIndex, 0, signerCount - 1));

        // Add signers
        address[] memory signers = new address[](signerCount);
        for (uint256 i = 0; i < signerCount; i++) {
            signers[i] = makeAddr(string(abi.encodePacked("bs", i)));
            vm.prank(admin);
            treasury.addSigner(signers[i]);
        }

        // Propose
        vm.prank(proposer);
        uint256 txId = treasury.proposeTransaction(
            recipient, 0, "", 0, 0, "bitmap", bytes32(0), bytes32(0), 0
        );

        // Approve with the selected index
        vm.prank(signers[approveIndex]);
        treasury.approveTransaction(txId);
        assertTrue(treasury.isApproved(txId, signers[approveIndex]), "should be approved");
    }

    /// @dev Test: execution finalizes budget and transfers funds correctly
    function test_ExecutionFinalizesBudget() public {
        uint256 budgetAllocation = 10 ether;
        uint256 spendAmount = 1 ether;

        address[] memory approvers = new address[](1);
        approvers[0] = admin;

        vm.prank(admin);
        bytes32 budgetId = treasury.createBudget(
            "Exec Budget", admin, budgetAllocation,
            uint64(block.timestamp), uint64(block.timestamp + 365 days),
            approvers, 1, spendAmount
        );

        vm.prank(proposer);
        uint256 txId = treasury.proposeTransaction(
            recipient, spendAmount, "", 0, 0, "Exec spend", bytes32(0), budgetId, spendAmount
        );

        vm.prank(admin);
        treasury.approveTransaction(txId);

        uint256 balanceBefore = recipient.balance;
        vm.prank(executor);
        treasury.executeTransaction(txId);

        uint256 available = treasury.getBudgetAvailable(budgetId);
        assertEq(available, budgetAllocation - spendAmount, "spent should be deducted");
        assertEq(recipient.balance - balanceBefore, spendAmount, "recipient should receive ETH");
    }
}
