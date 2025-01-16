// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToVoteBase} from "./ILockToVoteBase.sol";

/// @title ILockToApprove
/// @author Aragon X
/// @notice Governance plugin allowing token holders to use tokens locked without a snapshot requirement and engage in proposals immediately
interface ILockToApprove is ILockToVoteBase {
    /// @notice Returns wether the given address can approve or increase the amount of tokens assigned to aprove a proposal
    function canApprove(uint256 proposalId, address voter) external view returns (bool);

    /// @notice Registers an approval for the given proposal.
    /// @param proposalId The ID of the proposal to vote on.
    /// @param voter The address of the account whose vote will be registered
    /// @param newVotingPower The new balance that should be allocated to the voter. It can only be bigger.
    /// @dev newVotingPower updates any prior voting power, it does not add to the existing amount.
    function approve(uint256 proposalId, address voter, uint256 newVotingPower) external;

    /// @notice Reverts the existing voter's approval, if any.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter's address.
    function clearApproval(uint256 proposalId, address voter) external;

    /// @notice Updates the voting settings, which will be applied to the next proposal being created.
    /// @param newSettings The new settings, including the minimum approval ratio and the minimum proposal duration.
    function updatePluginSettings(LockToApproveSettings calldata newSettings) external;

    event Approved(uint256 proposalId, address voter, uint256 newVotingPower);
    event VoteCleared(uint256 proposalId, address voter);
    error ApprovalForbidden(uint256 proposalId, address voter);
}
