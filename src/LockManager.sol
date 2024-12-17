// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager, LockManagerSettings, UnlockMode} from "./interfaces/ILockManager.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizable.sol";
import {ILockToVote} from "./interfaces/ILockToVote.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockManager is ILockManager, DaoAuthorizable {
    /// @notice The current LockManager settings
    LockManagerSettings public settings;

    /// @notice The address of the lock to vote plugin to use
    ILockToVote public immutable plugin;

    /// @notice The address of the token contract
    IERC20 public immutable token;

    /// @notice Keeps track of the amount of tokens locked by address
    mapping(address => uint256) lockedBalances;

    /// @notice Keeps a list of the known active proposal ID's
    /// @dev Executed proposals will be actively reported, but defeated proposals will need to be garbage collected over time.
    uint256[] knownProposalIds;

    /// @notice Emitted when a token holder locks funds into the manager contract
    event BalanceLocked(address voter, uint256 amount);

    /// @notice Emitted when a token holder unlocks funds from the manager contract
    event BalanceUnlocked(address voter, uint256 amount);

    /// @notice Thrown when trying to assign an invalid lock mode
    error InvalidUnlockMode();

    /// @notice Thrown when the address calling proposalEnded() is not the plugin's
    error InvalidPluginAddress();

    /// @notice Raised when the caller holds no tokens or didn't lock any tokens
    error NoBalance();

    /// @notice Raised when attempting to unlock while active votes are cast in strict mode
    error LocksStillActive();

    constructor(
        IDAO _dao,
        LockManagerSettings memory _settings,
        ILockToVote _plugin,
        IERC20 _token
    ) DaoAuthorizable(_dao) {
        if (
            _settings.unlockMode != UnlockMode.STRICT &&
            _settings.unlockMode != UnlockMode.EARLY
        ) {
            revert InvalidUnlockMode();
        }

        settings.unlockMode = _settings.unlockMode;
        plugin = _plugin;
        token = _token;
    }

    /// @inheritdoc ILockManager
    function lock() public {
        _lock();
    }

    /// @inheritdoc ILockManager
    function lockAndVote(uint256 _proposalId) public {
        _lock();

        _vote(_proposalId);
    }

    /// @inheritdoc ILockManager
    function canVote(
        uint256 _proposalId,
        address _voter
    ) external view returns (bool) {
        uint256 availableBalance = lockedBalances[_voter] -
            plugin.usedVotingPower(_proposalId, _voter);
        if (availableBalance == 0) return false;

        (bool open, bool executed, ) = plugin.getProposal(_proposalId);
        return !executed && open;
    }

    /// @inheritdoc ILockManager
    function vote(uint256 _proposalId) public {
        _vote(_proposalId);
    }

    /// @inheritdoc ILockManager
    function unlock() public {
        if (lockedBalances[msg.sender] == 0) {
            revert NoBalance();
        }

        if (settings.unlockMode == UnlockMode.STRICT) {
            if (_hasActiveLocks()) revert LocksStillActive();
        } else {
            _withdrawActiveVotingPower();
        }

        // All votes clear

        uint256 _refundableBalance = lockedBalances[msg.sender];
        lockedBalances[msg.sender] = 0;

        // Withdraw
        token.transfer(msg.sender, _refundableBalance);
        emit BalanceUnlocked(msg.sender, _refundableBalance);
    }

    /// @inheritdoc ILockManager
    function proposalEnded(uint256 _proposalId) public {
        if (msg.sender != address(plugin)) {
            revert InvalidPluginAddress();
        }

        for (uint _i; _i < knownProposalIds.length; ) {
            if (knownProposalIds[_i] == _proposalId) {
                _removeKnownProposalId(_i);
                return;
            }
        }
    }

    // Internal

    function _lock() internal {
        uint256 _allowance = token.allowance(msg.sender, address(this));
        if (_allowance == 0) {
            revert NoBalance();
        }

        token.transferFrom(msg.sender, address(this), _allowance);
        lockedBalances[msg.sender] += _allowance;
        emit BalanceLocked(msg.sender, _allowance);
    }

    function _vote(uint256 _proposalId) internal {
        uint256 _newVotingPower = lockedBalances[msg.sender];
        if (_newVotingPower == 0) {
            revert NoBalance();
        } else if (
            _newVotingPower == plugin.usedVotingPower(_proposalId, msg.sender)
        ) {
            return;
        }

        plugin.vote(_proposalId, msg.sender, _newVotingPower);
    }

    function _hasActiveLocks() internal returns (bool) {
        uint256 _proposalCount = knownProposalIds.length;
        for (uint256 _i; _i < _proposalCount; ) {
            (bool open, ) = plugin.getProposal(knownProposalIds[_i]);
            if (!open) {
                _removeKnownProposalId(_i);
                _proposalCount = knownProposalIds.length;

                // Are we at the last item?
                if (_i == _proposalCount - 1) {
                    return false;
                }

                // Recheck the same index (now, another proposal)
                continue;
            }

            if (plugin.usedVotingPower(knownProposalIds[_i], msg.sender) > 0) {
                return true;
            }

            unchecked {
                _i++;
            }
        }
    }

    function _withdrawActiveVotingPower() internal {
        uint256 _proposalCount = knownProposalIds.length;
        for (uint256 _i; _i < _proposalCount; ) {
            (bool open, ) = plugin.getProposal(knownProposalIds[_i]);
            if (!open) {
                _removeKnownProposalId(_i);
                _proposalCount = knownProposalIds.length;

                // Are we at the last item?
                if (_i == _proposalCount - 1) {
                    return;
                }

                // Recheck the same index (now, another proposal)
                continue;
            }

            if (plugin.usedVotingPower(knownProposalIds[_i], msg.sender) > 0) {
                plugin.clearVote(knownProposalIds[_i], msg.sender);
            }

            unchecked {
                _i++;
            }
        }
    }

    /// @dev Cleaning up ended proposals, otherwise they would pile up and make unlocks more and more gas costly over time
    function _removeKnownProposalId(uint _arrayIndex) internal {
        uint _lastItemIdx = knownProposalIds.length - 1;

        // Swap the current item with the last, if needed
        if (_arrayIndex < _lastItemIdx) {
            knownProposalIds[_arrayIndex] = knownProposalIds[_lastItemIdx];
        }

        // Trim the array's last item
        knownProposalIds.pop();
    }
}
