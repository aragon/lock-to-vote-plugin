// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILockToVote} from "./interfaces/ILockToVote.sol";

contract LockToVotePlugin {
    // is ILockToVote
    struct PluginSettings {
        uint64 proposalDuration;
    }
}
