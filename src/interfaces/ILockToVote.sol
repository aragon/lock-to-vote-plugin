// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToVoteBase} from "./ILockToVoteBase.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

/// @notice A container for the voting settings that will be applied as parameters on proposal creation.
/// @param minVotingPower Minimum amount of allocated tokens required.
/// @param minApprovalPower Minimum amount of allocated YES votes.
/// @param supportThreshold Threshold of YES votes over the total participation required.
///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
/// @param minProposalDuration The minimum duration of the proposal voting stage in seconds.
struct LockToVoteSettings {
    uint256 minVotingPower;
    uint256 minApprovalPower;
    uint32 supportThreshold;
    uint64 minProposalDuration;
}

/// @notice A container for proposal-related information.
/// @param executed Whether the proposal is executed or not.
/// @param parameters The proposal parameters at the time of the proposal creation.
/// @param approvalTally The vote tally of the proposal.
/// @param votes The voting power cast by each voter.
/// @param actions The actions to be executed when the proposal passes.
/// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
///     If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts.
///     A failure map value of 0 requires every action to not revert.
/// @param targetConfig Configuration for the execution target, specifying the target address and operation type
///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
///     part of the `osx-commons-contracts` package, added in build 3.
struct ProposalVoting {
    bool executed;
    ProposalVotingParameters parameters;
    VoteTally tally;
    mapping(address => VoteItem) votes;
    Action[] actions;
    uint256 allowFailureMap;
    IPlugin.TargetConfig targetConfig;
}

struct VoteTally {
    uint256 yes;
    uint256 no;
    uint256 abstain;
}
struct VoteItem {
    VoteOption voteOption;
    uint256 votingPower;
}

/// @notice A container for the proposal parameters at the time of proposal creation.
/// @param minVotingPower Minimum amount of allocated tokens required.
/// @param minApprovalPower Minimum amount of allocated YES votes.
/// @param supportThreshold Threshold of YES votes over the total participation required.
///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
/// @param startDate The start date of the proposal vote.
/// @param endDate The end date of the proposal vote.
struct ProposalVotingParameters {
    uint256 minVotingPower;
    uint256 minApprovalPower;
    uint32 supportThreshold;
    uint64 startDate;
    uint64 endDate;
}

/// @notice Vote options that a voter can chose from.
/// @param None The default option state of a voter indicating the absence from the vote.
///     This option neither influences support nor participation.
/// @param Abstain This option does not influence the support but counts towards participation.
/// @param Yes This option increases the support and counts towards participation.
/// @param No This option decreases the support and counts towards participation.
enum VoteOption {
    None,
    Abstain,
    Yes,
    No
}

/// @title ILockToVote
/// @author Aragon X
/// @notice Governance plugin allowing token holders to use tokens locked without a snapshot requirement and engage in proposals immediately
interface ILockToVote is ILockToVoteBase {
    /// @notice Returns wether the given address can vote or increase the amount of tokens assigned to a proposal
    function canVote(uint256 proposalId, address voter) external view returns (bool);

    /// @notice Registers a vote for the given proposal.
    /// @param proposalId The ID of the proposal to vote on.
    /// @param voter The address of the account whose vote will be registered
    /// @param voteOption The value of the new vote to register. If an existing vote existed, it will be replaced.
    /// @param newVotingPower The new balance that should be allocated to the voter. It can only be bigger.
    /// @dev newVotingPower updates any prior voting power, it does not add to the existing amount.
    function vote(
        uint256 proposalId,
        address voter,
        VoteOption voteOption,
        uint256 newVotingPower
    ) external;

    /// @notice Reverts the existing voter's vote, if any.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter's address.
    function clearVote(uint256 proposalId, address voter) external;

    /// @notice Updates the voting settings, which will be applied to the next proposal being created.
    /// @param newSettings The new settings, including the minimum approval ratio and the minimum proposal duration.
    function updatePluginSettings(
        LockToVoteSettings calldata newSettings
    ) external;

    event VoteCast(
        uint256 proposalId,
        address voter,
        VoteOption voteOption,
        uint256 newVotingPower
    );
    event VoteCleared(uint256 proposalId, address voter);
    error VoteCastForbidden(uint256 proposalId, address voter);
    error VotingNoneForbidden(uint256 proposalId, address voter);
}
