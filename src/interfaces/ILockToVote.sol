// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

/// @title ILockToVote
/// @author Aragon X
/// @notice
interface ILockToVote {
    /// @notice getter function for the voting token.
    /// @dev public function also useful for registering interfaceId and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function votingToken() external view returns (IVotesUpgradeable);

    /// @notice Returns the approvalRatio parameter stored in the plugin settings.
    /// @return The approval ratio parameter, as a fraction of 1_000_000.
    function minApprovalRatio() external view returns (uint32);

    /// @notice Creates a new proposal.
    /// @param metadata The metadata of the proposal.
    /// @param actions The actions that will be executed after the proposal passes.
    /// @param duration The amount of seconds to allow for token holders to vote. NOTE: If the supplied value is zero, the proposal will be treated as an emergency one.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata metadata,
        IDAO.Action[] calldata actions,
        uint64 duration
    ) external returns (uint256 proposalId);

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
    /// @return The amount of balance that has been allocated for to the proposal by the given account.
    function votedBalance(
        uint256 proposalId,
        address voter
    ) external view returns (uint256);

    /// @notice Checks if the amount of locked votes for the given proposal is greater than the approval threshold.
    /// @param proposalId The ID of the proposal.
    /// @return Returns `true` if the total approval power against the proposal is greater or equal than the threshold and `false` otherwise.
    function isMinApprovalReached(
        uint256 proposalId
    ) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 proposalId) external view returns (bool);

    /// @notice Executes the given proposal.
    /// @param proposalId The ID of the proposal to execute.
    function execute(uint256 proposalId) external;

    /// @notice If the given proposal is no longer active, it allows to notify the manager.
    /// @param proposalId The ID of the proposal to clean up for.
    function releaseLock(uint256 proposalId) external;
}
