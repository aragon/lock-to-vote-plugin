// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILockToVotePlugin} from "./interfaces/ILockToVotePlugin.sol";

contract LockToVotePlugin is ILockToVotePlugin {
    struct PluginSettings {
        uint64 proposlDuration;
    }
}
