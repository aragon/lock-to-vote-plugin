// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToVote} from "./ILockToVote.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Defines whether locked funds can be unlocked at any time or not
enum UnlockMode {
    STRICT,
    EARLY
}

/// @notice The struct containing the LockManager helper settings
struct LockManagerSettings {
    /// @param lockMode The mode defining whether funds can be unlocked at any time or not
    UnlockMode unlockMode;
}

/// @title ILockManager
/// @author Aragon X
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
interface ILockManager {
    /// @notice Returns the address of the voting plugin.
    /// @return The LockToVote plugin address.
    function plugin() external view returns (ILockToVote);

    /// @notice Returns the address of the token contract used to determine the voting power.
    /// @return The token used for voting.
    function token() external view returns (IERC20);

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
