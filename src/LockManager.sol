// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILockManager} from "./interfaces/ILockManager.sol";

contract LockManager is ILockManager {
    struct PluginSettings {
        uint64 proposlDuration;
    }
}
