// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToGovernBase} from "./ILockToGovernBase.sol";
import {IMajorityVoting} from "./IMajorityVoting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Defines wether the voting plugin expects approvals or votes
///     Placeholder for future plugin variants
enum PluginMode {
    Voting
}

/// @notice The struct containing the LockManager helper settings. They are immutable after deployed.
struct LockManagerSettings {
    /// @notice The type of governance plugin expected
    PluginMode pluginMode;
}

/// @title ILockManager
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
interface ILockManager {
    /// @notice Returns the current settings of the LockManager.
    function settings() external view returns (PluginMode pluginMode);

    /// @notice Returns the address of the voting plugin.
    /// @return The LockToVote plugin address.
    function plugin() external view returns (ILockToGovernBase);

    /// @notice Returns the address of the token contract used to determine the voting power.
    /// @return The token used for voting.
    function token() external view returns (address);

    /// @notice Returns the currently locked balance that the given account has on the contract.
    function getLockedBalance(address account) external view returns (uint256);

    /// @notice Locks the balance currently allowed by msg.sender on this contract
    function lock() external;

    /// @notice Locks the given amount from msg.sender on this contract
    /// @param amount How many tokens the contract should lock
    function lock(uint256 amount) external;

    /// @notice Locks the balance currently allowed by msg.sender on this contract and registers the given vote on the target plugin
    /// @param proposalId The ID of the proposal where the vote will be registered
    /// @param vote The vote to cast (Yes, No, Abstain)
    function lockAndVote(uint256 proposalId, IMajorityVoting.VoteOption vote) external;

    /// @notice Locks the given amount from msg.sender on this contract and registers the given vote on the target plugin
    /// @param proposalId The ID of the proposal where the vote will be registered
    /// @param vote The vote to cast (Yes, No, Abstain)
    /// @param amount How many tokens the contract should lock and use for voting
    function lockAndVote(uint256 proposalId, IMajorityVoting.VoteOption vote, uint256 amount) external;

    /// @notice Uses the locked balance to vote on the given proposal for the registered plugin
    /// @param proposalId The ID of the proposal where the vote will be registered
    function vote(uint256 proposalId, IMajorityVoting.VoteOption vote) external;

    /// @notice Checks if an account can participate on a proposal. This can be because the proposal
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have any tokens locked.
    /// @param proposalId The proposal Id.
    /// @param voter The account address to be checked.
    /// @param voteOption The value of the new vote to register.
    /// @return Returns true if the account is allowed to vote.
    /// @dev The function assumes that the queried proposal exists.
    function canVote(uint256 proposalId, address voter, IMajorityVoting.VoteOption voteOption)
        external
        view
        returns (bool);

    /// @notice If the governance plugin allows it, releases all active locks placed on active proposals and transfers msg.sender's locked balance back. Depending on the current mode, it withdraws only if no locks are being used in active proposals.
    function unlock() external;

    /// @notice Called by the lock to vote plugin whenever a proposal is created. It instructs the manager to start tracking the given proposal.
    /// @param proposalId The ID of the proposal that msg.sender is reporting as created.
    function proposalCreated(uint256 proposalId) external;

    /// @notice Called by the lock to vote plugin whenever a proposal is executed (or ended). It instructs the manager to remove the proposal from the list of active proposal locks.
    /// @param proposalId The ID of the proposal that msg.sender is reporting as done.
    function proposalEnded(uint256 proposalId) external;

    /// @notice Defines the given plugin address as the target for voting
    function setPluginAddress(ILockToGovernBase _plugin) external;
}
