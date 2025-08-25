// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ILockManager, LockManagerSettings, PluginMode} from "../interfaces/ILockManager.sol";
import {ILockToGovernBase} from "../interfaces/ILockToGovernBase.sol";
import {ILockToVote} from "../interfaces/ILockToVote.sol";
import {IMajorityVoting} from "../interfaces/IMajorityVoting.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title LockManagerBase
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked tokens used to vote on LockToGovern plugins.
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

    /// @notice Keeps track of who created each known proposalId
    mapping(uint256 => address) public knownProposalIdCreators;

    /// @notice The address that can define the plugin address, once, after the deployment
    address immutable pluginSetter;

    /// @notice Emitted when a token holder locks funds into the LockManager contract.
    /// @param voter The address of the account locking tokens.
    /// @param amount The amount of tokens being added to the existing balance.
    event BalanceLocked(address indexed voter, uint256 amount);

    /// @notice Emitted when a token holder unlocks funds from the manager contract
    /// @param voter The address of the account unlocking tokens.
    /// @param amount The amount of tokens being unlocked.
    event BalanceUnlocked(address indexed voter, uint256 amount);

    /// @notice Emitted when the plugin reports a proposal as settled
    /// @param proposalId The ID the proposal where votes can no longer be submitted or cleared
    /// @dev The event could be emitted with a delay, compared to the effective proposal endDate
    event ProposalSettled(uint256 indexed proposalId);

    /// @notice Thrown when the address calling proposalSettled() is not the plugin's
    error InvalidPluginAddress();

    /// @notice Raised when the caller holds no tokens or didn't lock any tokens
    error NoBalance();

    /// @notice Raised when attempting to unlock while active votes are cast in strict mode
    error LocksStillActive();

    /// @notice Thrown when trying to set an invalid contract as the plugin
    error InvalidPlugin();

    /// @notice Thrown when trying to define the address of the plugin after it already was
    error SetPluginAddressForbidden();

    /// @notice Thrown when attempting to unlock with a created proposal that is still active
    /// @param proposalId The ID the active proposal
    error ProposalCreatedStillActive(uint256 proposalId);

    constructor() {
        settings.pluginMode = PluginMode.Voting;
        pluginSetter = msg.sender;
    }

    /// @notice Returns the known proposalID at the given index
    /// @param _index The position at which to read the proposalId
    /// @return The ID of the proposal at the given index
    function knownProposalIdAt(uint256 _index) public view virtual returns (uint256) {
        return knownProposalIds.at(_index);
    }

    /// @notice Returns the number of known proposalID's
    /// @return The number of known proposalID's
    function knownProposalIdsLength() public view virtual returns (uint256) {
        return knownProposalIds.length();
    }

    /// @notice Returns how many of the known proposalID's were created by the given address
    /// @param _creator The address to use for filtering
    function activeProposalsCreatedBy(address _creator) public view virtual returns (uint256 _result) {
        uint256 _proposalCount = knownProposalIds.length();
        for (uint256 _i; _i < _proposalCount; _i++) {
            uint256 _proposalId = knownProposalIds.at(_i);
            if (knownProposalIdCreators[_proposalId] != _creator) {
                continue;
            } else if (plugin.isProposalEnded(_proposalId)) {
                continue;
            }
            _result++;
        }
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
        _lock(_incomingTokenBalance());
        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function lockAndVote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption, uint256 _amount) public virtual {
        _lock(_amount);
        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function vote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) public virtual {
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

        /// @dev Withdraw the votes on active proposals
        /// @dev The plugin should revert if the voting mode doesn't allow to withdraw votes
        /// @dev Ensure that no active proposal was created by msg.sender
        _ensureCleanGovernance();

        // All votes and proposals are clear

        lockedBalances[msg.sender] = 0;

        // Withdraw
        _doUnlockTransfer(msg.sender, _refundableBalance);
        emit BalanceUnlocked(msg.sender, _refundableBalance);
    }

    /// @inheritdoc ILockManager
    function proposalCreated(uint256 _proposalId, address _creator) public virtual {
        if (msg.sender != address(plugin)) {
            revert InvalidPluginAddress();
        }

        // @dev Not checking for duplicate proposalId's
        // @dev The plugin already enforces unicity

        knownProposalIds.add(_proposalId);
        knownProposalIdCreators[_proposalId] = _creator;
    }

    /// @inheritdoc ILockManager
    function proposalSettled(uint256 _proposalId) public virtual {
        if (msg.sender != address(plugin)) {
            revert InvalidPluginAddress();
        }

        emit ProposalSettled(_proposalId);
        knownProposalIds.remove(_proposalId);
    }

    /// @inheritdoc ILockManager
    function setPluginAddress(ILockToGovernBase _newPluginAddress) public virtual {
        if (msg.sender != pluginSetter) {
            revert SetPluginAddressForbidden();
        } else if (address(plugin) != address(0)) {
            revert SetPluginAddressForbidden();
        } else if (!IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToGovernBase).interfaceId)) {
            revert InvalidPlugin();
        }
        // Is it the right type of plugin?
        else if (!IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToVote).interfaceId)) {
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

    /// @notice Clears the votes (if possible) on all active proposals and ensures that msg.sender created none of the active proposals
    function _ensureCleanGovernance() internal virtual {
        uint256 _proposalCount = knownProposalIds.length();
        for (uint256 _i; _i < _proposalCount;) {
            uint256 _proposalId = knownProposalIds.at(_i);
            if (plugin.isProposalEnded(_proposalId)) {
                knownProposalIds.remove(_proposalId);
                _proposalCount = knownProposalIds.length();

                // Were we at the last element?
                if (_i == _proposalCount) {
                    return;
                }

                // Recheck the same index (now, another proposalId)
                continue;
            }

            // The proposal is open

            if (knownProposalIdCreators[_proposalId] == msg.sender) {
                revert ProposalCreatedStillActive(_proposalId);
            }

            if (plugin.usedVotingPower(_proposalId, msg.sender) > 0) {
                /// @dev The plugin should revert if the voting mode doesn't allow it
                ILockToVote(address(plugin)).clearVote(_proposalId, msg.sender);
            }

            unchecked {
                _i++;
            }
        }
    }
}
