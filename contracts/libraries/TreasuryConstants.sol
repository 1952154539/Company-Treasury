// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant TREASURY_CONTROLLER_ROLE = keccak256("TREASURY_CONTROLLER_ROLE");
bytes32 constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
bytes32 constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
bytes32 constant BUDGET_MANAGER_ROLE = keccak256("BUDGET_MANAGER_ROLE");
bytes32 constant RECOVERY_ROLE = keccak256("RECOVERY_ROLE");

// Module names for moduleRegistry
bytes32 constant MODULE_YIELD = keccak256("MODULE_YIELD");
bytes32 constant MODULE_STREAMING = keccak256("MODULE_STREAMING");

// Magic values
bytes32 constant DONE_TIMESTAMP = bytes32(uint256(1));
uint256 constant MAX_BPS = 10_000;
uint256 constant MAX_SIGNERS = 256;
uint256 constant MIN_MIN_DELAY = 1 hours;
uint256 constant MAX_MIN_DELAY = 30 days;
uint256 constant MAX_RECOVERY_DELAY = 48 hours;
