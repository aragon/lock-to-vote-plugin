// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizable.sol";
import {ILockManager} from "./interfaces/ILockManager.sol";
import {ILockToVote} from "./interfaces/ILockToVote.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract LockManager is ILockManager, DaoAuthorizable {
    enum LockMode {
        STRICT,
        FLEXIBLE
    }
    struct Settings {
        LockMode lockMode;
    }

    Settings public settings;

    error InvalidLockMode();

    constructor(IDAO _dao, Settings memory _settings) DaoAuthorizable(_dao) {
        if (
            _settings.lockMode != LockMode.STRICT &&
            _settings.lockMode != LockMode.FLEXIBLE
        ) {
            revert InvalidLockMode();
        }

        settings.lockMode = _settings.lockMode;
    }

    /// @inheritdoc ILockManager
    function lock() public {
        //
    }

    /// @inheritdoc ILockManager
    function lockAndVote(ILockToVote plugin, uint256 proposalId) public {
        //
    }

    /// @inheritdoc ILockManager
    function vote(ILockToVote plugin, uint256 proposalId) public {
        //
    }

    /// @inheritdoc ILockManager
    function unlock() public {
        //
    }

    /// @inheritdoc ILockManager
    function releaseLock(uint256 proposalId) public {
        //
    }
}
