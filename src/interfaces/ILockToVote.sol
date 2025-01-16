// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToVoteBase} from "./ILockToVoteBase.sol";
import {IMajorityVoting} from "./IMajorityVoting.sol";

/// @title ILockToVote
/// @author Aragon X
/// @notice Governance plugin allowing token holders to use tokens locked without a snapshot requirement and engage in proposals immediately
interface ILockToVote is ILockToVoteBase {
    /// @notice Checks if an account can participate on a proposal. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have voting powers.
    /// - the voter can increase the amount of tokens assigned
    /// @param proposalId The proposal Id.
    /// @param voter The account address to be checked.
    /// @return Returns true if the account is allowed to vote.
    function canVote(
        uint256 proposalId,
        address voter
    ) external view returns (bool);

    /// @notice Votes on a proposal and, depending on the mode, executes it.
    /// @dev `voteOption`, 1 -> abstain, 2 -> yes, 3 -> no
    /// @param proposalId The ID of the proposal to vote on.
    /// @param voter The address of the account whose vote will be registered
    /// @param voteOption The value of the new vote to register. If an existing vote existed, it will be replaced.
    /// @param votingPower The new balance that should be allocated to the voter. It can only be bigger.
    /// @dev votingPower updates any prior voting power, it does not add to the existing amount.
    function vote(
        uint256 proposalId,
        address voter,
        IMajorityVoting.VoteOption voteOption,
        uint256 votingPower
    ) external;

    /// @notice Reverts the existing voter's vote, if existing.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter's address.
    function clearVote(uint256 proposalId, address voter) external;
}
