// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/// @title IMajorityVoting
/// @author Aragon X - 2022-2024
/// @notice The interface of majority voting plugin.
/// @custom:security-contact sirt@aragon.org
interface IMajorityVoting {
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

    /// @notice Emitted when a vote is cast by a voter.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter casting the vote.
    /// @param voteOption The casted vote option.
    /// @param votingPower The voting power behind this vote.
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteOption voteOption, uint256 votingPower);

    /// @notice Holds the state of an account's vote
    /// @param voteOption 1 -> abstain, 2 -> yes, 3 -> no
    /// @param votingPower How many tokens the account has allocated to `voteOption`
    struct VoteEntry {
        VoteOption voteOption;
        uint256 votingPower;
    }

    /// @notice Returns the support threshold parameter stored in the voting settings.
    /// @return The support threshold parameter.
    function supportThresholdRatio() external view returns (uint32);

    /// @notice Returns the minimum participation parameter stored in the voting settings.
    /// @return The minimum participation parameter.
    function minParticipationRatio() external view returns (uint32);

    /// @notice Returns the configured minimum approval ratio.
    /// @return The minimal approval ratio.
    function minApprovalRatio() external view returns (uint256);

    /// @notice Checks if the support value defined as:
    ///     $$\texttt{support} = \frac{N_\text{yes}}{N_\text{yes}+N_\text{no}}$$
    ///     for a proposal is greater than the support threshold.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the  support is greater than the support threshold and `false` otherwise.
    function isSupportThresholdReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if the participation value defined as:
    ///     $$\texttt{participation} = \frac{N_\text{yes}+N_\text{no}+N_\text{abstain}}{N_\text{total}}$$
    ///     for a proposal is greater or equal than the minimum participation value.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the participation is greater or equal than the minimum participation,
    ///     and `false` otherwise.
    function isMinVotingPowerReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if the min approval value defined as:
    ///     $$\texttt{minApprovalRatio} = \frac{N_\text{yes}}{N_\text{total}}$$
    ///     for a proposal is greater or equal than the minimum approval value.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the approvals is greater or equal than the minimum approval and `false` otherwise.
    function isMinApprovalReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);

    /// @notice Executes a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;

    /// @notice Returns whether the account has voted for the proposal.
    /// @dev May return `none` if the `_proposalId` does not exist,
    ///      or the `_account` does not have voting power.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return The vote option cast by a voter for a certain proposal.
    function getVote(uint256 _proposalId, address _account) external view returns (VoteEntry memory);
}
