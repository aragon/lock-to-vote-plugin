// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToVote} from "./ILockToVote.sol";

/// @title ILockManager
/// @author Aragon X
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
interface ILockManager {
    /// @notice Locks the balance currently allowed by msg.sender on this contract
    function lock() external;

    /// @notice Locks the balance currently allowed by msg.sender on this contract and registers a vote on the target plugin
    /// @param proposalId The ID of the proposal where the vote will be registered
    function lockAndVote(uint256 proposalId) external;

    /// @notice Uses the locked balance to place a vote on the given proposal for the given plugin
    /// @param proposalId The ID of the proposal where the vote will be registered
    function vote(uint256 proposalId) external;

    /// @notice Checks if an account can participate on a proposal. This can be because the proposal
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have any tokens locked.
    /// @param proposalId The proposal Id.
    /// @param voter The account address to be checked.
    /// @return Returns true if the account is allowed to vote.
    /// @dev The function assumes that the queried proposal exists.
    function canVote(
        uint256 proposalId,
        address voter
    ) external view returns (bool);

    /// @notice If the mode allows it, releases all active locks placed on active proposals and transfers msg.sender's locked balance back. Depending on the current mode, it withdraws only if no locks are being used in active proposals.
    function unlock() external;

    /// @notice Called by the lock to vote plugin whenever a proposal is executed (or ended). It instructs the manager to remove the proposal from the list of active proposal locks.
    /// @param proposalId The ID of the proposal that msg.sender is reporting as done.
    function proposalEnded(uint256 proposalId) external;
}
