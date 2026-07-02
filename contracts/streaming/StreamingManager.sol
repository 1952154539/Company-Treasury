// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ReentrancyGuardTransient} from
    "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITreasuryEvents} from "../interfaces/ITreasuryEvents.sol";
import {
    StreamNotFound,
    StreamNotActive,
    StreamNotCancelable,
    StreamCliffNotReached,
    StreamNotStarted,
    NoReleasableAmount,
    InvalidStreamDuration,
    StreamAmountZero,
    ZeroAddress,
    InvalidAmount,
    NotAuthorized,
    ContractPaused
} from "../interfaces/ITreasuryErrors.sol";
import {
    DEFAULT_ADMIN_ROLE,
    BUDGET_MANAGER_ROLE,
    TREASURY_CONTROLLER_ROLE,
    MODULE_STREAMING
} from "../libraries/TreasuryConstants.sol";

struct StreamData {
    uint256 id;
    address sender;
    address recipient;
    address token;
    uint256 totalAmount;
    uint256 remainingBalance;
    uint64 startTime;
    uint64 cliffDuration;
    uint64 endTime;
    uint256 lastWithdrawalTime;
    uint256 withdrawnAmount;
    bool cancelable;
    bool active;
    bytes32 budgetId;
}

// ERC-7201 storage
// keccak256(abi.encode(uint256(keccak256("treasury.streaming.storage")) - 1)) & ~bytes32(uint256(0xff))
library StreamingStorage {
    bytes32 private constant STORAGE_SLOT =
        0x9c7f7d7e7b8e3e0d5a3c1e9e7a5b3d1f7e9c7b5a3d1f5e9a7b3d1f5e7a9b3e00;

    struct Layout {
        mapping(uint256 => StreamData) streams;
        uint256 streamCounter;
        address treasuryCore;
        bool paused;
        uint256[47] __gap;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

interface ITreasuryStreaming {
    function transferETH(address payable to, uint256 amount) external;
    function transferERC20(address token, address to, uint256 amount) external;
}

contract StreamingManager is
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardTransient,
    ITreasuryEvents
{
    using SafeERC20 for IERC20;

    bytes32 public constant STREAM_CREATOR_ROLE = keccak256("STREAM_CREATOR_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address treasury) external initializer {
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STREAM_CREATOR_ROLE, admin);
        _grantRole(TREASURY_CONTROLLER_ROLE, admin);

        if (treasury == address(0)) revert ZeroAddress();
        StreamingStorage.layout().treasuryCore = treasury;
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ---- Stream Management ----

    function createStream(
        address recipient,
        address token,
        uint256 amount,
        uint64 startTime,
        uint64 cliffDuration,
        uint64 endTime,
        bool cancelable,
        bytes32 budgetId
    ) public onlyRole(STREAM_CREATOR_ROLE) returns (uint256 streamId) {
        StreamingStorage.Layout storage $ = StreamingStorage.layout();
        if ($.paused) revert ContractPaused();
        if (recipient == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert StreamAmountZero();
        if (startTime >= endTime) revert InvalidStreamDuration(startTime, endTime);

        streamId = ++$.streamCounter;

        StreamData storage s = $.streams[streamId];
        s.id = streamId;
        s.sender = $.treasuryCore;
        s.recipient = recipient;
        s.token = token;
        s.totalAmount = amount;
        s.remainingBalance = amount;
        s.startTime = startTime;
        s.cliffDuration = cliffDuration;
        s.endTime = endTime;
        s.lastWithdrawalTime = startTime;
        s.cancelable = cancelable;
        s.active = true;
        s.budgetId = budgetId;

        emit StreamCreated(streamId, $.treasuryCore, recipient, token, amount, startTime, endTime, cliffDuration, cancelable);
    }

    function batchCreateStreams(
        address[] calldata recipients,
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint64[] calldata startTimes,
        uint64[] calldata cliffDurations,
        uint64[] calldata endTimes,
        bool[] calldata cancelables
    ) external onlyRole(STREAM_CREATOR_ROLE) returns (uint256[] memory streamIds) {
        uint256 len = recipients.length;
        streamIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            streamIds[i] = createStream(
                recipients[i],
                tokens[i],
                amounts[i],
                startTimes[i],
                cliffDurations[i],
                endTimes[i],
                cancelables[i],
                bytes32(0)
            );
        }
    }

    function cancelStream(uint256 streamId) external {
        StreamingStorage.Layout storage $ = StreamingStorage.layout();
        StreamData storage s = $.streams[streamId];
        if (!s.active) revert StreamNotActive(streamId);
        if (!s.cancelable) revert StreamNotCancelable(streamId);
        if (!hasRole(STREAM_CREATOR_ROLE, msg.sender)) revert NotAuthorized(msg.sender, STREAM_CREATOR_ROLE);

        s.active = false;
        uint256 remaining = s.remainingBalance;
        s.remainingBalance = 0;

        emit StreamCancelled(streamId, remaining, $.treasuryCore);
    }

    function withdrawFromStream(uint256 streamId) public nonReentrant returns (uint256 amount) {
        StreamingStorage.Layout storage $ = StreamingStorage.layout();
        StreamData storage s = $.streams[streamId];
        if (!s.active) revert StreamNotActive(streamId);
        if (msg.sender != s.recipient) revert NotAuthorized(msg.sender, DEFAULT_ADMIN_ROLE);
        if (block.timestamp < s.startTime) revert StreamNotStarted(streamId);

        amount = _releasableAmount(s);
        if (amount == 0) revert NoReleasableAmount(streamId);

        s.withdrawnAmount += amount;
        s.remainingBalance -= amount;
        s.lastWithdrawalTime = block.timestamp;

        // Transfer from TreasuryCore to recipient
        if (s.token == address(0)) {
            ITreasuryStreaming($.treasuryCore).transferETH(payable(msg.sender), amount);
        } else {
            ITreasuryStreaming($.treasuryCore).transferERC20(s.token, msg.sender, amount);
        }

        emit StreamWithdrawn(streamId, msg.sender, amount);
    }

    function withdrawFromStreams(uint256[] calldata streamIds)
        external
        nonReentrant
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](streamIds.length);
        for (uint256 i = 0; i < streamIds.length; i++) {
            amounts[i] = withdrawFromStream(streamIds[i]);
        }
    }

    // ---- Streaming math ----

    function _vestedAmount(StreamData storage s) internal view returns (uint256) {
        uint64 now_ = uint64(block.timestamp);
        if (now_ <= s.startTime) return 0;
        if (now_ >= s.endTime) return s.totalAmount;

        // Cliff check
        if (s.cliffDuration > 0 && now_ < s.startTime + s.cliffDuration) {
            return 0;
        }

        // Linear vesting: total * (t - start) / (end - start)
        return s.totalAmount * (now_ - s.startTime) / (s.endTime - s.startTime);
    }

    function _releasableAmount(StreamData storage s) internal view returns (uint256) {
        uint256 vested = _vestedAmount(s);
        if (vested <= s.withdrawnAmount) return 0;
        return vested - s.withdrawnAmount;
    }

    // ---- Admin functions ----

    function setPaused(bool paused) external onlyRole(TREASURY_CONTROLLER_ROLE) {
        StreamingStorage.layout().paused = paused;
    }

    function setTreasuryCore(address treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury == address(0)) revert ZeroAddress();
        StreamingStorage.layout().treasuryCore = treasury;
    }

    // ---- View functions ----

    function getStream(uint256 streamId) external view returns (StreamData memory) {
        StreamingStorage.Layout storage $ = StreamingStorage.layout();
        if ($.streams[streamId].totalAmount == 0) revert StreamNotFound(streamId);
        return $.streams[streamId];
    }

    function vestedAmount(uint256 streamId) external view returns (uint256) {
        StreamingStorage.Layout storage $ = StreamingStorage.layout();
        if (!$.streams[streamId].active) revert StreamNotFound(streamId);
        return _vestedAmount($.streams[streamId]);
    }

    function releasableAmount(uint256 streamId) external view returns (uint256) {
        StreamingStorage.Layout storage $ = StreamingStorage.layout();
        if (!$.streams[streamId].active) revert StreamNotFound(streamId);
        return _releasableAmount($.streams[streamId]);
    }

    function getStreamCount() external view returns (uint256) {
        return StreamingStorage.layout().streamCounter;
    }

    function getTreasuryCore() external view returns (address) {
        return StreamingStorage.layout().treasuryCore;
    }

    // Storage gap
    uint256[49] private __streamingGap;
}
