// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager, LockManagerSettings, UnlockMode, PluginMode} from "./interfaces/ILockManager.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {ILockToVoteBase} from "./interfaces/ILockToVoteBase.sol";
import {ILockToApprove} from "./interfaces/ILockToApprove.sol";
import {ILockToVote} from "./interfaces/ILockToVote.sol";
import {IMajorityVoting} from "./interfaces/IMajorityVoting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title LockManager
/// @author Aragon X 2024
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
contract LockManager is ILockManager, DaoAuthorizable {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice The current LockManager settings
    LockManagerSettings public settings;

    /// @notice The address of the lock to vote plugin to use
    ILockToVoteBase public plugin;

    /// @notice The address of the token contract
    IERC20 public immutable token;

    /// @notice The address of the underlying token from which "token" originates, if applicable
    IERC20 immutable underlyingTokenAddress;

    /// @notice Keeps track of the amount of tokens locked by address
    mapping(address => uint256) public lockedBalances;

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

    /// @notice Thrown when trying to assign an invalid lock mode
    error InvalidUnlockMode();

    /// @notice Thrown when the address calling proposalEnded() is not the plugin's
    error InvalidPluginAddress();

    /// @notice Raised when the caller holds no tokens or didn't lock any tokens
    error NoBalance();

    /// @notice Raised when trying to vote on a proposal with the same balance as the last time
    error NoNewBalance();

    /// @notice Raised when attempting to unlock while active votes are cast in strict mode
    error LocksStillActive();

    /// @notice Thrown when trying to set an invalid contract as the plugin
    error InvalidPlugin();

    /// @notice Thrown when trying to set an invalid PluginMode value, or when trying to use an operation not supported by the current pluginMode
    error InvalidPluginMode();

    /// @notice Thrown when trying to define the address of the plugin after it already was
    error SetPluginAddressForbidden();

    constructor(IDAO _dao, LockManagerSettings memory _settings, IERC20 _token, IERC20 _underlyingToken)
        DaoAuthorizable(_dao)
    {
        if (_settings.unlockMode != UnlockMode.Strict && _settings.unlockMode != UnlockMode.Early) {
            revert InvalidUnlockMode();
        } else if (_settings.pluginMode != PluginMode.Approval && _settings.pluginMode != PluginMode.Voting) {
            revert InvalidPluginMode();
        }

        settings.unlockMode = _settings.unlockMode;
        settings.pluginMode = _settings.pluginMode;
        token = _token;
        underlyingTokenAddress = _underlyingToken;
    }

    /// @notice Returns the known proposalID at the given index
    function knownProposalIdAt(uint256 _index) public view virtual returns (uint256) {
        return knownProposalIds.at(_index);
    }

    /// @inheritdoc ILockManager
    function lock() public virtual {
        _lock();
    }

    /// @inheritdoc ILockManager
    function lockAndApprove(uint256 _proposalId) public virtual {
        if (settings.pluginMode != PluginMode.Approval) {
            revert InvalidPluginMode();
        }

        _lock();

        _approve(_proposalId);
    }

    /// @inheritdoc ILockManager
    function lockAndVote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) public virtual {
        if (settings.pluginMode != PluginMode.Voting) {
            revert InvalidPluginMode();
        }

        _lock();

        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function approve(uint256 _proposalId) public virtual {
        if (settings.pluginMode != PluginMode.Approval) {
            revert InvalidPluginMode();
        }

        _approve(_proposalId);
    }

    /// @inheritdoc ILockManager
    function vote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) public virtual {
        if (settings.pluginMode != PluginMode.Voting) {
            revert InvalidPluginMode();
        }

        _vote(_proposalId, _voteOption);
    }

    /// @inheritdoc ILockManager
    function canVote(uint256 _proposalId, address _voter, IMajorityVoting.VoteOption _voteOption)
        external
        view
        virtual
        returns (bool)
    {
        if (settings.pluginMode == PluginMode.Voting) {
            return ILockToVote(address(plugin)).canVote(_proposalId, _voter, _voteOption);
        }
        return ILockToApprove(address(plugin)).canApprove(_proposalId, _voter);
    }

    /// @inheritdoc ILockManager
    function unlock() public virtual {
        if (lockedBalances[msg.sender] == 0) {
            revert NoBalance();
        }

        if (settings.unlockMode == UnlockMode.Strict) {
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
    function underlyingToken() external view virtual returns (IERC20) {
        if (address(underlyingTokenAddress) == address(0)) {
            return token;
        }
        return underlyingTokenAddress;
    }

    /// @inheritdoc ILockManager
    function setPluginAddress(ILockToVoteBase _newPluginAddress) public virtual {
        if (address(plugin) != address(0)) {
            revert SetPluginAddressForbidden();
        } else if (!IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToVoteBase).interfaceId)) {
            revert InvalidPlugin();
        }
        // Is it the right type of plugin?
        else if (
            settings.pluginMode == PluginMode.Approval
                && !IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToApprove).interfaceId)
        ) {
            revert InvalidPlugin();
        } else if (
            settings.pluginMode == PluginMode.Voting
                && !IERC165(address(_newPluginAddress)).supportsInterface(type(ILockToVote).interfaceId)
        ) {
            revert InvalidPlugin();
        }

        plugin = _newPluginAddress;
    }

    // Internal

    function _lock() internal virtual {
        uint256 _allowance = token.allowance(msg.sender, address(this));
        if (_allowance == 0) {
            revert NoBalance();
        }

        token.transferFrom(msg.sender, address(this), _allowance);
        lockedBalances[msg.sender] += _allowance;
        emit BalanceLocked(msg.sender, _allowance);
    }

    function _approve(uint256 _proposalId) internal virtual {
        uint256 _currentVotingPower = lockedBalances[msg.sender];
        if (_currentVotingPower == 0) {
            revert NoBalance();
        } else if (_currentVotingPower == plugin.usedVotingPower(_proposalId, msg.sender)) {
            revert NoNewBalance();
        }

        ILockToApprove(address(plugin)).approve(_proposalId, msg.sender, _currentVotingPower);
    }

    function _vote(uint256 _proposalId, IMajorityVoting.VoteOption _voteOption) internal virtual {
        uint256 _currentVotingPower = lockedBalances[msg.sender];
        if (_currentVotingPower == 0) {
            revert NoBalance();
        } else if (_currentVotingPower == plugin.usedVotingPower(_proposalId, msg.sender)) {
            revert NoNewBalance();
        }

        ILockToVote(address(plugin)).vote(_proposalId, msg.sender, _voteOption, _currentVotingPower);
    }

    function _hasActiveLocks() internal virtual returns (bool _activeLocks) {
        uint256 _proposalCount = knownProposalIds.length();
        for (uint256 _i; _i < _proposalCount;) {
            uint256 _proposalId = knownProposalIds.at(_i);
            if (!plugin.isProposalOpen(_proposalId)) {
                knownProposalIds.remove(_proposalId);
                _proposalCount = knownProposalIds.length();

                // Were we at the last element?
                if (_i == _proposalCount) {
                    return false;
                }

                // Recheck the same index (now, another proposalId)
                continue;
            }

            if (plugin.usedVotingPower(_proposalId, msg.sender) > 0) {
                return true;
            }

            unchecked {
                _i++;
            }
        }
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
                if (settings.pluginMode == PluginMode.Voting) {
                    ILockToVote(address(plugin)).clearVote(_proposalId, msg.sender);
                } else {
                    ILockToApprove(address(plugin)).clearApproval(_proposalId, msg.sender);
                }
            }

            unchecked {
                _i++;
            }
        }
    }
}
