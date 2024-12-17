// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx-commons-contracts/dao/IDAO.sol";
import {Action} from "@aragon/osx-commons-contracts/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/plugin/PluginUUPSUpgradeable.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/plugin/IPlugin.sol";

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
struct Proposal {
    bool executed;
    ProposalParameters parameters;
    uint256 approvalTally;
    mapping(address => uint256) votes;
    Action[] actions;
    uint256 allowFailureMap;
    IPlugin.TargetConfig targetConfig;
}

/// @notice A container for the proposal parameters at the time of proposal creation.
/// @param minApprovalRatio The approval threshold above which the proposal becomes executable.
///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
/// @param startDate The start date of the proposal vote.
/// @param endDate The end date of the proposal vote.
struct ProposalParameters {
    uint32 minApprovalRatio;
    uint64 startDate;
    uint64 endDate;
}

/// @notice A container for the voting settings that will be applied as parameters on proposal creation.
/// @param minApprovalRatio The support threshold value.
///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
/// @param minProposalDuration The minimum duration of the proposal voting stage in seconds.
struct LockToVoteSettings {
    uint32 minApprovalRatio;
    uint64 minProposalDuration;
}

/// @title ILockToVote
/// @author Aragon X
/// @notice
interface ILockToVote {
    /// @notice Returns the address of the token contract used to determine the voting power.
    /// @return The token used for voting.
    function votingToken() external view returns (IERC20);

    /// @notice Registers an approval vote for the given proposal.
    /// @param proposalId The ID of the proposal to vote on.
    /// @param voter The address of the account whose vote will be registered
    /// @param newVotingPower The new balance that should be allocated to the voter. It can only be bigger.
    /// @dev newVotingPower updates any prior voting power, it does not add to the existing amount.
    function vote(
        uint256 proposalId,
        address voter,
        uint newVotingPower
    ) external;

    /// @notice Reverts the existing voter's vote, if any.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter's address.
    function clearVote(uint256 proposalId, address voter) external;

    /// @notice Returns whether the account has voted for the proposal.
    /// @param proposalId The ID of the proposal.
    /// @param voter The account address to be checked.
    /// @return The amount of balance that has been allocated to the proposal by the given account.
    function usedVotingPower(
        uint256 proposalId,
        address voter
    ) external view returns (uint256);

    /// @notice Checks if the amount of locked votes for the given proposal is greater than the approval threshold.
    /// @param proposalId The ID of the proposal.
    /// @return Returns `true` if the total approval power against the proposal is greater or equal than the threshold and `false` otherwise.
    function isMinApprovalReached(
        uint256 proposalId
    ) external view returns (bool);

    /// @notice If the given proposal is no longer active, it allows to notify the manager.
    /// @param proposalId The ID of the proposal to clean up for.
    function releaseLock(uint256 proposalId) external;

    error NoVotingPower();
    error ProposalAlreadyExists(uint256 proposalId);
    error DateOutOfBounds(uint256 limit, uint256 actual);
}
