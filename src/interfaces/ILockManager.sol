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
    /// @param plugin The address of the lock to vote plugin where the lock will be used
    /// @param proposalId The ID of the proposal where the vote will be registered
    function lockAndVote(ILockToVote plugin, uint256 proposalId) external;

    /// @notice Uses the locked balance to place a vote on the given proposal for the given plugin
    /// @param plugin The address of the lock to vote plugin where the locked balance will be used
    /// @param proposalId The ID of the proposal where the vote will be registered
    function vote(ILockToVote plugin, uint256 proposalId) external;

    /// @notice If the mode allows it, releases all active locks placed on active proposals and transfers msg.sender's locked balance back. Depending on the current mode, it withdraws only if no locks are being used in active proposals.
    function unlock() external;

    /// @notice Called by a lock to vote plugin whenever a proposal is executed. It instructs the manager to remove the proposal from the list of active proposal locks.
    /// @param proposalId The ID of the proposal that msg.sender is reporting as done.
    function releaseLock(uint256 proposalId) external;
}
