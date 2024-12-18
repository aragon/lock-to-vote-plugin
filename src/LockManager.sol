// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {ILockManager, LockManagerSettings, UnlockMode} from "./interfaces/ILockManager.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {ILockToVote} from "./interfaces/ILockToVote.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title LockManager
/// @author Aragon X 2024
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
contract LockManager is ILockManager, DaoAuthorizable {
    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_SETTINGS_PERMISSION_ID = keccak256("UPDATE_SETTINGS_PERMISSION");

    /// @notice The current LockManager settings
    LockManagerSettings public settings;

    /// @notice The address of the lock to vote plugin to use
    ILockToVote public plugin;

    /// @notice The address of the token contract
    IERC20 public immutable token;

    /// @notice The address of the underlying token from which "token" originates, if applicable
    IERC20 immutable underlyingTokenAddress;

    /// @notice Keeps track of the amount of tokens locked by address
    mapping(address => uint256) public lockedBalances;

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

    /// @notice Thrown when trying to set an invalid contract as the plugin
    error InvalidPlugin();

    /// @notice Thrown when trying to define the address of the plugin after it already was
    error CannotUpdatePlugin();

    constructor(IDAO _dao, LockManagerSettings memory _settings, IERC20 _token, IERC20 _underlyingToken)
        DaoAuthorizable(_dao)
    {
        if (_settings.unlockMode != UnlockMode.STRICT && _settings.unlockMode != UnlockMode.EARLY) {
            revert InvalidUnlockMode();
        }

        settings.unlockMode = _settings.unlockMode;
        token = _token;
        underlyingTokenAddress = _underlyingToken;
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
    function vote(uint256 _proposalId) public {
        _vote(_proposalId);
    }

    /// @inheritdoc ILockManager
    function canVote(uint256 _proposalId, address _voter) external view returns (bool) {
        return plugin.canVote(_proposalId, _voter);
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

        for (uint256 _i; _i < knownProposalIds.length;) {
            if (knownProposalIds[_i] == _proposalId) {
                _removeKnownProposalId(_i);
                return;
            }
        }
    }

    /// @inheritdoc ILockManager
    function underlyingToken() external view returns (IERC20) {
        if (address(underlyingTokenAddress) == address(0)) {
            return token;
        }
        return underlyingTokenAddress;
    }

    /// @inheritdoc ILockManager
    function setPluginAddress(ILockToVote _plugin) public auth(UPDATE_SETTINGS_PERMISSION_ID) {
        if (!IERC165(address(_plugin)).supportsInterface(type(ILockToVote).interfaceId)) {
            revert InvalidPlugin();
        } else if (address(plugin) != address(0)) {
            revert CannotUpdatePlugin();
        }

        plugin = _plugin;
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
        } else if (_newVotingPower == plugin.usedVotingPower(_proposalId, msg.sender)) {
            return;
        }

        plugin.vote(_proposalId, msg.sender, _newVotingPower);
    }

    function _hasActiveLocks() internal returns (bool _activeLocks) {
        uint256 _proposalCount = knownProposalIds.length;
        for (uint256 _i; _i < _proposalCount;) {
            if (!plugin.isProposalOpen(knownProposalIds[_i])) {
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
        for (uint256 _i; _i < _proposalCount;) {
            if (!plugin.isProposalOpen(knownProposalIds[_i])) {
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
    function _removeKnownProposalId(uint256 _arrayIndex) internal {
        uint256 _lastItemIdx = knownProposalIds.length - 1;

        // Swap the current item with the last, if needed
        if (_arrayIndex < _lastItemIdx) {
            knownProposalIds[_arrayIndex] = knownProposalIds[_lastItemIdx];
        }

        // Trim the array's last item
        knownProposalIds.pop();
    }
}
