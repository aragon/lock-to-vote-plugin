// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager, LockManagerSettings, PluginMode} from "../interfaces/ILockManager.sol";
import {ILockToGovernBase} from "../interfaces/ILockToGovernBase.sol";
import {ILockToVote} from "../interfaces/ILockToVote.sol";
import {IMajorityVoting} from "../interfaces/IMajorityVoting.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title LockManagerBase
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
abstract contract LockManagerBase is ILockManager {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice The current LockManager settings
    LockManagerSettings public settings;

    /// @notice The address of the lock to vote plugin to use
    ILockToGovernBase public plugin;

    /// @notice Keeps track of the amount of tokens locked by address
    mapping(address => uint256) private lockedBalances;

    /// @notice Keeps track of the known active proposal ID's
    /// @dev NOTE: Executed proposals will be actively reported, but defeated proposals will need to be garbage collected over time.
    EnumerableSet.UintSet internal knownProposalIds;

    /// @notice Emitted when a token holder locks funds into the manager contract
    event BalanceLocked(address voter, uint256 amount);

    /// @notice Emitted when a token holder unlocks funds from the manager contract
    event BalanceUnlocked(address voter, uint256 amount);

    /// @notice Emitted when the plugin reports a proposal as ended
    /// @param proposalId The ID the proposal where votes can no longer be submitted or cleared
    event ProposalEnded(uint256 proposalId);

    /// @notice Thrown when the address calling proposalEnded() is not the plugin's
    error InvalidPluginAddress();

    /// @notice Raised when the caller holds no tokens or didn't lock any tokens
    error NoBalance();

    /// @notice Raised when attempting to unlock while active votes are cast in strict mode
    error LocksStillActive();

    /// @notice Thrown when trying to set an invalid contract as the plugin
    error InvalidPlugin();

    /// @notice Thrown when trying to set an invalid PluginMode value, or when trying to use an operation not supported by the current pluginMode
    error InvalidPluginMode();

    /// @notice Thrown when trying to define the address of the plugin after it already was
    error SetPluginAddressForbidden();

    /// @param _settings The operation mode of the contract (plugin mode)
    constructor(LockManagerSettings memory _settings) {
        settings.pluginMode = _settings.pluginMode;
    }

    /// @notice Returns the known proposalID at the given index
    function knownProposalIdAt(uint256 _index) public view virtual returns (uint256) {
        return knownProposalIds.at(_index);
    }

    /// @notice Returns the number of known proposalID's
    function knownProposalIdsLength() public view virtual returns (uint256) {
        return knownProposalIds.length();
    }

    /// @inheritdoc ILockManager
    function lock() public virtual {
        _lock(_incomingTokenBalance());
    }

    /// @inheritdoc ILockManager
    function lock(uint256 _amount) public virtual {
        _lock(_amount);
    }

    /// @inheritdoc ILockManager
    function lockAndVote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) public virtual {
        if (settings.pluginMode != PluginMode.Voting) {
            revert InvalidPluginMode();
        }

        _lock(_incomingTokenBalance());
        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function lockAndVote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption, uint256 _amount) public virtual {
        if (settings.pluginMode != PluginMode.Voting) {
            revert InvalidPluginMode();
        }

        _lock(_amount);
        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function vote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) public virtual {
        if (settings.pluginMode != PluginMode.Voting) {
            revert InvalidPluginMode();
        }

        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function getLockedBalance(address _account) public view virtual returns (uint256) {
        return lockedBalances[_account];
    }

    /// @inheritdoc ILockManager
    function canVote(uint256 _proposalId, address _voter, IMajorityVoting.VoteOption _voteOption)
        external
        view
        virtual
        returns (bool)
    {
        return ILockToVote(address(plugin)).canVote(_proposalId, _voter, _voteOption);
    }

    /// @inheritdoc ILockManager
    function unlock() public virtual {
        uint256 _refundableBalance = getLockedBalance(msg.sender);
        if (_refundableBalance == 0) {
            revert NoBalance();
        }

        /// @dev The plugin may decide to revert if its voting mode doesn't allow for it
        _withdrawActiveVotingPower();

        // All votes clear

        lockedBalances[msg.sender] = 0;

        // Withdraw
        _doUnlockTransfer(msg.sender, _refundableBalance);
        emit BalanceUnlocked(msg.sender, _refundableBalance);
    }

    /// @inheritdoc ILockManager
    function proposalCreated(uint256 _proposalId) public virtual {
        if (msg.sender != address(plugin)) {
            revert InvalidPluginAddress();
        }

        // @dev Not checking for duplicate proposalId's
        // @dev Both plugins already enforce unicity

        knownProposalIds.add(_proposalId);
    }

    /// @inheritdoc ILockManager
    function proposalEnded(uint256 _proposalId) public virtual {
        if (msg.sender != address(plugin)) {
            revert InvalidPluginAddress();
        }

        emit ProposalEnded(_proposalId);
        knownProposalIds.remove(_proposalId);
    }

    /// @inheritdoc ILockManager
    function setPluginAddress(ILockToGovernBase _newPluginAddress) public virtual {
        if (address(plugin) != address(0)) {
            revert SetPluginAddressForbidden();
        } else if (!IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToGovernBase).interfaceId)) {
            revert InvalidPlugin();
        }
        // Is it the right type of plugin?
        else if (
            settings.pluginMode == PluginMode.Voting
                && !IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToVote).interfaceId)
        ) {
            revert InvalidPlugin();
        }

        plugin = _newPluginAddress;
    }

    // Internal

    /// @notice Returns the amount of tokens that LockManager receives or can transfer from msg.sender
    function _incomingTokenBalance() internal view virtual returns (uint256);

    /// @notice Takes the user's tokens and registers the received amount.
    function _lock(uint256 _amount) internal virtual {
        if (_amount == 0) {
            revert NoBalance();
        }

        /// @dev Reverts if not enough balance is approved
        _doLockTransfer(_amount);

        lockedBalances[msg.sender] += _amount;
        emit BalanceLocked(msg.sender, _amount);
    }

    /// @notice Triggers the transfer needed in order to complete the token locking flow.
    ///     Reverts if the requested amount cannot be locked.
    function _doLockTransfer(uint256 _amount) internal virtual;

    /// @notice Transfers the requested amount of tokens to the recipient
    /// @param _recipient The address that will receive the locked tokens back
    /// @param _amount The amount of tokens that the recipient will get
    function _doUnlockTransfer(address _recipient, uint256 _amount) internal virtual;

    function _vote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) internal virtual {
        uint256 _currentVotingPower = getLockedBalance(msg.sender);

        /// @dev The voting power value is checked within plugin.vote()

        ILockToVote(address(plugin)).vote(_proposalId, msg.sender, _voteOption, _currentVotingPower);
    }

    function _withdrawActiveVotingPower() internal virtual {
        uint256 _proposalCount = knownProposalIds.length();
        for (uint256 _i; _i < _proposalCount;) {
            uint256 _proposalId = knownProposalIds.at(_i);
            if (!plugin.isProposalOpen(_proposalId)) {
                knownProposalIds.remove(_proposalId);
                _proposalCount = knownProposalIds.length();

                // Were we at the last element?
                if (_i == _proposalCount) {
                    return;
                }

                // Recheck the same index (now, another proposalId)
                continue;
            }

            if (plugin.usedVotingPower(_proposalId, msg.sender) > 0) {
                ILockToVote(address(plugin)).clearVote(_proposalId, msg.sender);
            }

            unchecked {
                _i++;
            }
        }
    }
}
