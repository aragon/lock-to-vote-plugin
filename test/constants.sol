// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

bytes32 constant PROPOSER_PERMISSION_ID = keccak256("PROPOSER_PERMISSION");
bytes32 constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
bytes32 constant UPDATE_SETTINGS_PERMISSION_ID = keccak256(
    "UPDATE_SETTINGS_PERMISSION"
);
bytes32 constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256(
    "UPGRADE_PLUGIN_PERMISSION"
);
bytes32 constant ROOT_PERMISSION_ID = keccak256("ROOT_PERMISSION");

uint64 constant MAX_UINT64 = uint64(2 ** 64 - 1);
address constant ADDRESS_ZERO = address(0x0);
address constant NO_CONDITION = ADDRESS_ZERO;

// Actors
address constant ALICE_ADDRESS = address(
    0xa11ce00000000a11ce00000000a11ce0000000
);
address constant BOB_ADDRESS = address(
    0xB0B00000000B0B00000000B0B00000000B0B00
);
address constant CAROL_ADDRESS = address(
    0xc460100000000c460100000000c46010000000
);
address constant DAVID_ADDRESS = address(
    0xd471d00000000d471d00000000d471d0000000
);