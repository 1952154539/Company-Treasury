// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TreasuryCore} from "../../contracts/treasury/TreasuryCore.sol";
import {StreamingManager} from "../../contracts/streaming/StreamingManager.sol";
import {YieldManager} from "../../contracts/yield/YieldManager.sol";
import {TreasuryFactory, TreasuryDeployment} from "../../contracts/factory/TreasuryFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {
    DEFAULT_ADMIN_ROLE,
    PROPOSER_ROLE,
    EXECUTOR_ROLE,
    STRATEGIST_ROLE,
    MODULE_YIELD,
    MODULE_STREAMING
} from "../../contracts/libraries/TreasuryConstants.sol";

contract StreamingFuzzTest is Test {
    TreasuryCore public treasury;
    StreamingManager public streaming;
    MockERC20 public usdc;

    address public admin = makeAddr("admin");
    address public recipient = makeAddr("recipient");
    address public alice = makeAddr("alice");

    function setUp() public {
        TreasuryFactory factory = new TreasuryFactory();
        address[] memory signers = new address[](1);
        signers[0] = admin;
        TreasuryDeployment memory d = factory.deploy(admin, signers, 1, 0);
        treasury = d.treasuryCore;
        streaming = d.streamingManager;

        vm.startPrank(admin);
        treasury.registerModule(MODULE_STREAMING, address(streaming));
        streaming.grantRole(streaming.STREAM_CREATOR_ROLE(), alice);
        treasury.grantRole(PROPOSER_ROLE, alice);
        treasury.grantRole(EXECUTOR_ROLE, alice);
        vm.stopPrank();

        usdc = new MockERC20("USDC", "USDC", 6);
        usdc.mint(address(treasury), 1_000_000_000e6);
    }

    /// @dev Fuzz: vestedAmount at endTime must equal totalAmount
    function testFuzz_VestedAtEndTime(
        uint256 totalAmount,
        uint64 startTime,
        uint64 duration
    ) public {
        totalAmount = bound(totalAmount, 1, 1_000_000e6);
        startTime = uint64(bound(startTime, 1, type(uint64).max - 365 days));
        duration = uint64(bound(duration, 1 days, 365 days));
        uint64 endTime = startTime + duration;

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient, address(usdc), totalAmount, startTime, 0, endTime, false, bytes32(0)
        );

        // Warp to endTime
        vm.warp(endTime);
        uint256 vested = streaming.vestedAmount(streamId);
        assertEq(vested, totalAmount, "vested at endTime should equal total");
    }

    /// @dev Fuzz: vestedAmount at startTime must be 0
    function testFuzz_VestedAtStartTime(
        uint256 totalAmount,
        uint64 startTime,
        uint64 duration
    ) public {
        totalAmount = bound(totalAmount, 1, 1_000_000e6);
        startTime = uint64(bound(startTime, 100, type(uint64).max - 365 days));
        duration = uint64(bound(duration, 1 days, 365 days));

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient, address(usdc), totalAmount, startTime, 0, startTime + duration, false, bytes32(0)
        );

        // Don't warp — still at startTime
        uint256 vested = streaming.vestedAmount(streamId);
        assertEq(vested, 0, "vested at start should be 0");
    }

    /// @dev Fuzz: released + withdrawn should never exceed vested
    function testFuzz_ReleasableNeverExceedsVested(
        uint256 totalAmount,
        uint64 startTime,
        uint64 duration,
        uint64 warpRatio
    ) public {
        totalAmount = bound(totalAmount, 1, 1_000_000e6);
        startTime = uint64(bound(startTime, 1, type(uint64).max - 365 days));
        duration = uint64(bound(duration, 1 days, 365 days));
        // Warp to somewhere between start and end
        warpRatio = uint64(bound(warpRatio, 1, 99)); // 1% to 99%
        uint64 endTime = startTime + duration;
        uint64 warpTime = startTime + uint64((uint256(duration) * warpRatio) / 100);

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient, address(usdc), totalAmount, startTime, 0, endTime, true, bytes32(0)
        );

        vm.warp(warpTime);
        uint256 vested = streaming.vestedAmount(streamId);
        uint256 releasable = streaming.releasableAmount(streamId);

        assertGe(vested, releasable, "vested >= releasable");
        assertLe(vested, totalAmount, "vested <= total");
    }

    /// @dev Fuzz: cliff enforces zero vested before cliff ends
    function testFuzz_CliffEnforced(
        uint256 totalAmount,
        uint64 startTime,
        uint64 duration,
        uint64 cliffDuration
    ) public {
        totalAmount = bound(totalAmount, 1, 1_000_000e6);
        startTime = uint64(bound(startTime, 1, type(uint64).max - 365 days));
        duration = uint64(bound(duration, 30 days, 365 days));
        cliffDuration = uint64(bound(cliffDuration, 1 days, duration - 1 days));
        uint64 endTime = startTime + duration;

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient, address(usdc), totalAmount, startTime, cliffDuration, endTime, false, bytes32(0)
        );

        // Warp to just before cliff ends
        uint64 rightBeforeCliff = startTime + cliffDuration - 1;
        vm.warp(rightBeforeCliff);
        uint256 vestedBeforeCliff = streaming.vestedAmount(streamId);
        assertEq(vestedBeforeCliff, 0, "vested before cliff should be 0");
    }

    /// @dev Fuzz: withdrawn amount accumulates correctly
    function testFuzz_WithdrawalAccumulation(
        uint256 totalAmount,
        uint64 duration
    ) public {
        totalAmount = bound(totalAmount, 1000, 1_000_000e6);
        duration = uint64(bound(duration, 10 days, 365 days));
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = startTime + duration;

        vm.prank(alice);
        uint256 streamId = streaming.createStream(
            recipient, address(usdc), totalAmount, startTime, 0, endTime, true, bytes32(0)
        );

        // Withdraw at 50%
        vm.warp(startTime + duration / 2);
        uint256 balanceBefore = usdc.balanceOf(recipient);
        vm.prank(recipient);
        streaming.withdrawFromStream(streamId);
        uint256 firstReceived = usdc.balanceOf(recipient) - balanceBefore;

        // Withdraw remaining at end
        vm.warp(endTime + 1);
        uint256 balanceBefore2 = usdc.balanceOf(recipient);
        vm.prank(recipient);
        streaming.withdrawFromStream(streamId);
        uint256 secondReceived = usdc.balanceOf(recipient) - balanceBefore2;

        uint256 totalReceived = firstReceived + secondReceived;
        assertApproxEqAbs(totalReceived, totalAmount, 2, "total withdrawn should equal totalAmount");
    }
}
