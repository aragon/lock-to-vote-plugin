// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizable.sol";
import {ILockManager} from "./interfaces/ILockManager.sol";
import {ILockToVote} from "./interfaces/ILockToVote.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockManager is ILockManager, DaoAuthorizable {
    /// @notice Defines whether locked funds can be unlocked at any time or not
    enum UnlockMode {
        STRICT,
        EARLY
    }

    /// @notice The struct containing the LockManager helper settings
    struct Settings {
        /// @param lockMode The mode defining whether funds can be unlocked at any time or not
        UnlockMode unlockMode;
        /// @param plugin The address of the lock to vote plugin to use
        ILockToVote plugin;
        /// @param token The address of the token contract
        IERC20 token;
    }

    /// @notice The current LockManager settings
    Settings public settings;

    /// @notice Keeps track of the amount of tokens locked by address
    mapping(address => uint256) lockedBalance;

    /// @notice Keeps a list of the known active proposal ID's
    /// @dev Executed proposals will be actively reported, but defeated proposals will need to be garbage collected over time.
    uint256[] knownProposalIds;

    /// @notice Thrown when trying to assign an invalid lock mode
    error InvalidUnlockMode();

    /// @notice Raised when the caller holds no tokens or didn't lock any tokens
    error NoBalance();

    /// @notice Raised when attempting to unlock while active votes are cast in strict mode
    error LocksStillActive();

    constructor(IDAO _dao, Settings memory _settings) DaoAuthorizable(_dao) {
        if (
            _settings.unlockMode != UnlockMode.STRICT &&
            _settings.unlockMode != UnlockMode.EARLY
        ) {
            revert InvalidUnlockMode();
        }

        settings.unlockMode = _settings.unlockMode;
        settings.plugin = _settings.plugin;
        settings.token = _settings.token;
    }

    /// @inheritdoc ILockManager
    function lock() public {
        // Register the token if not present
        //
    }

    /// @inheritdoc ILockManager
    function lockAndVote(uint256 proposalId) public {
        //
    }

    /// @inheritdoc ILockManager
    function vote(uint256 proposalId) public {
        uint256 newVotingPower = lockedBalance[msg.sender];
        settings.plugin.vote(proposalId, msg.sender, newVotingPower);
    }

    /// @inheritdoc ILockManager
    function unlock() public {
        if (lockedBalance[msg.sender] == 0) {
            revert NoBalance();
        }

        if (settings.unlockMode == UnlockMode.STRICT) {
            if (hasActiveLocks()) revert LocksStillActive();
        } else {
            withdrawActiveVotingPower();
        }

        // All votes clear

        // Refund
        uint256 refundBalance = lockedBalance[msg.sender];
        lockedBalance[msg.sender] = 0;

        settings.token.transfer(msg.sender, refundBalance);
    }

    /// @inheritdoc ILockManager
    function releaseLock(uint256 proposalId) public {
        //
    }

    // Internal

    function hasActiveLocks() internal returns (bool) {
        uint256 _proposalCount = knownProposalIds.length;
        for (uint256 _i; _i < _proposalCount; ) {
            (bool open, ) = settings.plugin.getProposal(knownProposalIds[_i]);
            if (!open) {
                cleanKnownProposalId(_i);

                // Are we at the last item?
                /// @dev Comparing to `_proposalCount` instead of `_proposalCount - 1`, because the array is now shorter
                if (_i == _proposalCount) {
                    return false;
                }

                // Recheck the same index (now, another proposal)
                continue;
            }

            if (settings.plugin.hasVoted(msg.sender)) {
                return true;
            }

            unchecked {
                _i++;
            }
        }
    }

    function withdrawActiveVotingPower() internal {
        uint256 _proposalCount = knownProposalIds.length;
        for (uint256 _i; _i < _proposalCount; ) {
            (bool open, ) = settings.plugin.getProposal(knownProposalIds[_i]);
            if (!open) {
                cleanKnownProposalId(_i);

                // Are we at the last item?
                /// @dev Comparing to `_proposalCount` instead of `_proposalCount - 1`, because the array is now shorter
                if (_i == _proposalCount) {
                    return;
                }

                // Recheck the same index (now, another proposal)
                continue;
            }

            uint votedBalance = settings.plugin.votedBalance(msg.sender);
            if (votedBalance > 0) {
                settings.plugin.clearVote(knownProposalIds[_i], msg.sender);
            }

            unchecked {
                _i++;
            }
        }
    }

    /// @dev Cleaning up ended proposals, otherwise they would pile up and make unlocks more and more gas costly over time
    function cleanKnownProposalId(uint _arrayIndex) internal {
        // Swap the current item with the last, if needed
        if (_arrayIndex < knownProposalIds.length - 1) {
            knownProposalIds[_arrayIndex] = knownProposalIds[
                knownProposalIds.length - 1
            ];
        }

        // Trim the array's last item
        knownProposalIds.length -= 1;
    }
}
